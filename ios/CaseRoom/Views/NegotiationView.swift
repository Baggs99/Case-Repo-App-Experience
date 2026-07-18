/*
 * Purpose: Dark case-negotiation stage (canvas 4a nego) — the pre-lobby screen
 *          where the interviewer opens with a pick, the candidate accepts or
 *          counters ONCE, and the interviewer resolves. The candidate reads
 *          "THEY KEPT THEIR PICK" (verbatim) when the interviewer keeps their
 *          round-1 pick over a counter. Re-skinned onto the dark takeover
 *          palette (inherits RootShell's .dsTheme(.dark) seam).
 * Inputs: NegotiationViewModel (its own network state) + the host
 *         SessionViewModel (peer name, stamped case id, negotiationTick, and
 *         refreshDetail() to advance into the lobby on accept).
 * Outputs: none.
 * Run: shown by SessionView while state == "negotiating" (and held through the
 *      negotiating→lobby flip while a candidate resolution is unacknowledged).
 */

import SwiftUI

struct NegotiationStageView: View {
    @Bindable var viewModel: NegotiationViewModel
    var sessionViewModel: SessionViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                Spacer(minLength: 20)

                center

                Spacer(minLength: 20)

                footer
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.refresh(stampedCaseId: sessionViewModel.caseId) }
    }

    // MARK: - Header (CASE NEGOTIATION · ONE COUNTER EACH)

    private var header: some View {
        HStack(alignment: .center) {
            Text("CASE NEGOTIATION")
                .dsText(.kicker)
                .foregroundStyle(palette.muted)
            Spacer()
            Text("ONE COUNTER EACH")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.13)
                .foregroundStyle(palette.faint)
        }
    }

    // MARK: - Center (role-routed)

    @ViewBuilder
    private var center: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.view == nil, viewModel.isLoading {
                loadingRow
            } else if isInterviewer {
                interviewerBody
            } else {
                candidateBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Candidate

    @ViewBuilder
    private var candidateBody: some View {
        if let requested = viewModel.view?.candidateRequestedCase {
            requestBlock(requested)
                .padding(.bottom, 16)
        }

        switch viewModel.candidateStage {
        case .waitingForPick:
            waitingRow("\(peerName) is choosing the case…")
        case .decide(let pick):
            pickHero(pick, resolutionLabel: nil)
        case .counterSent:
            waitingRow("Counter sent — your one round, used…")
        case .keptPick(let pick):
            pickHero(pick, resolutionLabel: "THEY KEPT THEIR PICK")
        case .tookCounter(let counter):
            pickHero(counter, resolutionLabel: "THEY TOOK YOUR COUNTER")
        case .none:
            waitingRow("Loading the case negotiation…")
        }
    }

    /// The candidate's request, echoed back (RequestedCaseBrief) — canvas
    /// "YOUR REQUEST — SENT WITH YOUR PROFILE".
    private func requestBlock(_ requested: RequestedCaseBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR REQUEST — SENT WITH YOUR PROFILE")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 5)
            Text(requested.title)
                .dsText(.rowTitle)
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    /// The single glass hero: the interviewer's pick (decide) or the resolved
    /// card ("THEY KEPT THEIR PICK" / took-counter). `resolutionLabel` nil =
    /// live decide state with Accept + Counter; non-nil = terminal with Begin.
    private func pickHero(_ brief: NegotiatedCaseBrief, resolutionLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(resolutionLabel ?? "THEIR PICK")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 6)

            Text(brief.title)
                .font(.archivo(17, weight: 700))
                .tracking(17 * -0.015)
                .foregroundStyle(palette.ink)
                .padding(.bottom, 3)

            if let meta = briefMeta(brief) {
                Text(meta)
                    .font(.archivo(11.5))
                    .foregroundStyle(palette.muted)
            }

            Spacer().frame(height: 16)

            if resolutionLabel == nil {
                primaryButton("Begin with this", height: 48) {
                    await accept(brief.caseId)
                }
                .padding(.bottom, 8)
                underlineButton("Counter — ask for your request") {
                    await counter()
                }
                .frame(maxWidth: .infinity)
            } else {
                primaryButton("Begin", height: 48) {
                    await beginFromResolution()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 26)
    }

    // MARK: - Interviewer

    @ViewBuilder
    private var interviewerBody: some View {
        switch viewModel.interviewerStage {
        case .choosePick(let sources):
            interviewerPickList(sources)
        case .awaitingCandidate(let pick):
            VStack(alignment: .leading, spacing: 16) {
                staticCard(kicker: "YOUR PICK — SENT", brief: pick)
                waitingRow("Waiting on \(peerName)'s counter or accept…")
            }
        case .resolve(let pick, let counter):
            interviewerResolve(pick: pick, counter: counter)
        case .none:
            waitingRow("Loading the case negotiation…")
        }
    }

    @ViewBuilder
    private func interviewerPickList(_ sources: PickSources?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PICK A CASE FOR \(peerName.uppercased())")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 14)

            if let recs = sources?.recommendedForCandidate, !recs.isEmpty {
                sectionLabel("RECOMMENDED FOR THEM")
                ForEach(recs) { rec in
                    proposeRow(title: rec.title, meta: recMeta(rec), caseId: rec.caseId)
                }
            }

            if let doneSet = sources?.interviewerDoneSet, !doneSet.isEmpty {
                sectionLabel("YOUR DONE SET")
                    .padding(.top, 18)
                ForEach(doneSet, id: \.caseId) { brief in
                    proposeRow(title: brief.title, meta: briefMeta(brief), caseId: brief.caseId)
                }
            }

            if sources?.libraryAllowed == true {
                Text("Or open the full library to pick any case.")
                    .dsText(.serif(12.5, italic: true))
                    .foregroundStyle(palette.faint)
                    .padding(.top, 16)
            }
        }
    }

    private func interviewerResolve(pick: NegotiatedCaseBrief, counter: NegotiatedCaseBrief) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(peerName.uppercased()) COUNTERED")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)

            staticCard(kicker: "YOUR PICK", brief: pick)
            staticCard(kicker: "THEIR COUNTER", brief: counter)

            primaryButton("Keep my pick", height: 48) { await accept(pick.caseId) }
            underlineButton("Take their case instead") { await accept(counter.caseId) }
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proposeRow(title: String, meta: String?, caseId: Int) -> some View {
        Button {
            Task { await viewModel.propose(caseId: caseId) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsText(.rowTitle)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let meta {
                    Text(meta)
                        .font(.archivo(11))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        }
        .buttonStyle(DSPressStyle())
        .disabled(viewModel.isSubmitting)
    }

    private func staticCard(kicker: String, brief: NegotiatedCaseBrief) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker)
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)
            Text(brief.title)
                .font(.archivo(15, weight: 700))
                .foregroundStyle(palette.ink)
            if let meta = briefMeta(brief) {
                Text(meta)
                    .font(.archivo(11.5))
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        // §5: page content is SQUARE and never an outlined box — a flat block
        // set off by a hairline rule (matching proposeRow / requestBlock), not a
        // rounded strokeBorder card. Glass panels/chips/sheets stay rounded.
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.archivo(9, weight: 600))
            .tracking(9 * 0.12)
            .foregroundStyle(palette.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }

    // MARK: - Shared affordances

    private var loadingRow: some View { waitingRow("Loading the case negotiation…") }

    private func waitingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            MutedPulseDot()
            Text(text)
                .dsText(.serif(15, italic: true))
                .foregroundStyle(palette.muted)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("No back-and-forth beyond one counter. In person, just talk.")
            .dsText(.serif(12, italic: true))
            .foregroundStyle(palette.faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ title: String, height: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(13.5, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(palette.ink))
        }
        .buttonStyle(DSPressStyle())
        .disabled(viewModel.isSubmitting)
    }

    private func underlineButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(12.5, weight: 600))
                .foregroundStyle(palette.muted)
                .underline(true, pattern: .solid)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
    }

    // MARK: - Actions

    private func accept(_ caseId: Int) async {
        let stamped = await viewModel.accept(caseId: caseId)
        if stamped { await sessionViewModel.refreshDetail() }
    }

    private func counter() async {
        // The candidate's single counter re-requests their own case; when no
        // request is echoed, fall back to the pick id (server still gates round).
        guard let caseId = viewModel.view?.candidateRequestedCase?.caseId
                ?? viewModel.view?.currentPick?.caseId else { return }
        await viewModel.propose(caseId: caseId)
    }

    private func beginFromResolution() async {
        viewModel.resolutionAcknowledged = true
        await sessionViewModel.refreshDetail()
    }

    // MARK: - Derived

    private var isInterviewer: Bool { sessionViewModel.role == "interviewer" }

    private var peerName: String {
        (isInterviewer ? sessionViewModel.candidateName : sessionViewModel.interviewerName) ?? "Your peer"
    }

    private func briefMeta(_ brief: NegotiatedCaseBrief) -> String? {
        metaLine([brief.caseType, brief.difficulty])
    }

    private func recMeta(_ rec: Recommendation) -> String? {
        metaLine([rec.caseType, rec.difficulty])
    }

    private func metaLine(_ parts: [String?]) -> String? {
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}

/// A small muted dot that pulses for the negotiation waiting states (canvas
/// uses the muted #7C8CA8, not the green BlinkDot).
private struct MutedPulseDot: View {
    @Environment(\.dsPalette) private var palette
    @State private var dim = false
    var body: some View {
        Circle()
            .fill(palette.muted)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.2 : 1)
            .onAppear { withAnimation(DSMotion.blink) { dim = true } }
    }
}

#if DEBUG
#Preview("Candidate — decide") {
    NavigationStack {
        NegotiationStageView(
            viewModel: NegotiationViewModel(
                fixtureView: NegotiationPreview.candidateDecide, resolution: nil),
            sessionViewModel: NegotiationPreview.sessionVM(role: "candidate")
        )
    }
    .dsTheme(.dark)
}

#Preview("Candidate — THEY KEPT THEIR PICK") {
    NavigationStack {
        NegotiationStageView(
            viewModel: NegotiationViewModel(
                fixtureView: NegotiationPreview.candidateKept, resolution: .keptPick),
            sessionViewModel: NegotiationPreview.sessionVM(role: "candidate")
        )
    }
    .dsTheme(.dark)
}

#Preview("Interviewer — choose pick") {
    NavigationStack {
        NegotiationStageView(
            viewModel: NegotiationViewModel(
                fixtureView: NegotiationPreview.interviewerChoose, resolution: nil),
            sessionViewModel: NegotiationPreview.sessionVM(role: "interviewer")
        )
    }
    .dsTheme(.dark)
}
#endif
