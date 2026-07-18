/*
 * Purpose: Candidate's dark LIVE screen (canvas 4a live + 4b exhibit-open) — the
 *          glass clock pill, the striped interviewer pane, the case title, the
 *          CASE/EX segmented pills (new-dot on a freshly-revealed exhibit), and
 *          the revealed exhibit rendered natively as a volumes/fares table +
 *          unit-cost bars. A reveal raises an F0 toast. All exhibit state comes
 *          from ExhibitsViewModel's already-published reveal path (the
 *          .reveal → decrypt seam is untouched); this view only observes it.
 * Inputs: an ExhibitsViewModel (shared with SessionViewModel so inbound .reveal
 *         messages reach its decrypt path); the case title/kicker + peer name +
 *         whether to show the compact peer pane, supplied by SessionView.
 * Outputs: none.
 * Run: shown by SessionView while state == "live" for the candidate.
 */

import SwiftUI

struct CandidateLiveView: View {
    @State private var viewModel: ExhibitsViewModel
    var caseTitle: String?
    var caseKicker: String?
    var peerName: String
    var showsInterviewerPane: Bool
    /// Land directly on a newly-revealed exhibit instead of raising the toast —
    /// false in production (always toast); only the 4b held-still shot sets it.
    var autoOpenOnReveal: Bool = false

    @State private var clockStart = Date()
    @State private var selection: LiveSelection = .caseBrief
    @State private var seen: Set<Int> = []
    @State private var previouslyRevealed: Set<Int> = []
    @State private var toast: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsPalette) private var palette

    enum LiveSelection: Equatable {
        case caseBrief
        case exhibit(Int)
    }

    init(
        viewModel: ExhibitsViewModel,
        caseTitle: String? = nil,
        caseKicker: String? = nil,
        peerName: String = "Your interviewer",
        showsInterviewerPane: Bool = false,
        autoOpenOnReveal: Bool = false
    ) {
        _viewModel = State(initialValue: viewModel)
        self.caseTitle = caseTitle
        self.caseKicker = caseKicker
        self.peerName = peerName
        self.showsInterviewerPane = showsInterviewerPane
        self.autoOpenOnReveal = autoOpenOnReveal
    }

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                caseTitleBlock
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                pillBar
                    .padding(.top, 14)

                endButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .onChange(of: revealedIDs) { _, newValue in handleReveals(newValue) }
        .dsToast(item: $toast)
    }

    // MARK: - Header (clock pill + striped interviewer pane)

    private var header: some View {
        HStack(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                LiveClockPill(text: SessionClock.mmss(context.date.timeIntervalSince(clockStart)))
            }
            Spacer()
            if showsInterviewerPane {
                PeerVideoPane(name: peerName)
            }
        }
    }

    // MARK: - Case title

    @ViewBuilder
    private var caseTitleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let caseKicker {
                Text(caseKicker)
                    .font(.archivo(9, weight: 600))
                    .tracking(9 * 0.15)
                    .foregroundStyle(palette.muted)
            }
            if let caseTitle {
                Text(caseTitle)
                    .font(.archivo(17, weight: 700))
                    .tracking(17 * -0.015)
                    .foregroundStyle(palette.ink)
            }
        }
    }

    // MARK: - Content (CASE prompt or the selected exhibit)

    @ViewBuilder
    private var contentArea: some View {
        switch selection {
        case .caseBrief:
            casePrompt
        case .exhibit(let exhibitId):
            if let meta = viewModel.exhibits.first(where: { $0.exhibitId == exhibitId }) {
                ScrollView { exhibitBody(meta).padding(.top, 18) }
                    .scrollIndicators(.hidden)
            } else {
                casePrompt
            }
        }
    }

    private var casePrompt: some View {
        VStack(spacing: 18) {
            StaircaseMark()
                .stroke(palette.hairline, lineWidth: 4)
                .aspectRatio(48.0 / 40.0, contentMode: .fit)
                .frame(width: 72, height: 60)
                .opacity(0.5)
            Text("Listen. Exhibits appear here when \(peerName) releases them.")
                .dsText(.serif(15, italic: true))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func exhibitBody(_ meta: ExhibitMeta) -> some View {
        switch viewModel.state(for: meta.exhibitId) {
        case .revealed(let data):
            if let content = ExhibitContent.decode(from: data) {
                ExhibitContentView(panelLabel: LivePresentation.panelLabel(idx: meta.idx), content: content)
            } else if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                exhibitUnavailable
            }
        case .locked:
            exhibitUnavailable
        }
    }

    private var exhibitUnavailable: some View {
        Text("Couldn't display this exhibit.")
            .dsText(.serif(14, italic: true))
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Segmented CASE / EX pills

    private var pillBar: some View {
        HStack(spacing: 6) {
            pill(label: "CASE", active: selection == .caseBrief, newDot: false) {
                selection = .caseBrief
            }
            ForEach(revealedExhibits, id: \.exhibitId) { meta in
                pill(
                    label: LivePresentation.pillLabel(idx: meta.idx),
                    active: selection == .exhibit(meta.exhibitId),
                    newDot: newDotIDs.contains(meta.exhibitId)
                ) {
                    open(meta.exhibitId)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(label: String, active: Bool, newDot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.archivo(11, weight: 600))
                    .tracking(11 * 0.08)
                    .foregroundStyle(active ? palette.onInk : palette.muted)
                if newDot {
                    Circle().fill(palette.green).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(active ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(palette.ink.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(DSPressStyle())
    }

    private var endButton: some View {
        Button { dismiss() } label: {
            Text("End interview")
                .font(.archivo(11.5, weight: 600))
                .foregroundStyle(palette.muted)
                .underline(true, pattern: .solid)
                .padding(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reveal handling (toast + open), observing the VM's state only

    private func open(_ exhibitId: Int) {
        selection = .exhibit(exhibitId)
        seen.insert(exhibitId)
    }

    private func handleReveals(_ current: Set<Int>) {
        let newlyRevealed = current.subtracting(previouslyRevealed)
        previouslyRevealed = current
        guard let latest = revealedExhibits.last, newlyRevealed.contains(latest.exhibitId) else { return }
        if autoOpenOnReveal {
            // 4b held-still shot: land straight on the open exhibit, no toast.
            open(latest.exhibitId)
        } else {
            toast = LivePresentation.revealToast(idx: latest.idx)
        }
    }

    // MARK: - Derived

    private var revealedExhibits: [ExhibitMeta] {
        viewModel.exhibits
            .filter { if case .revealed = viewModel.state(for: $0.exhibitId) { return true } else { return false } }
            .sorted { $0.idx < $1.idx }
    }

    private var revealedIDs: Set<Int> { Set(revealedExhibits.map(\.exhibitId)) }

    private var newDotIDs: Set<Int> {
        LivePresentation.newDotIds(revealed: revealedIDs, seen: seen)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CandidateLiveView(
            viewModel: ExhibitsViewModel(sessionId: 1, service: APIClient.shared),
            caseTitle: "Low-cost carrier enters the Nordic market",
            caseKicker: "MARKET ENTRY · D4 · KELLOGG 2019",
            peerName: "M. Lindqvist",
            showsInterviewerPane: true
        )
    }
    .dsTheme(.dark)
}
#endif
