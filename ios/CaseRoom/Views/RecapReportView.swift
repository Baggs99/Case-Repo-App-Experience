/*
 * Purpose: Recap REPORT page (F5 Task 6, canvas 6b) — the post-session feedback
 *          a candidate must read before their seat reopens. LIGHT palette (this
 *          is daylight, not the dark takeover): a masthead (case title +
 *          interviewer attribution), the rubric bars (points/max, tabular
 *          values, e.g. 7/5/8/6), the interviewer's serif prose (notes_md
 *          paragraphs + any per-item notes), and an attached case-pack PDF row
 *          (the Library striped-thumb look, replicated) that opens the case.
 *          Read-only: the REQUIRED 1–5 close-out rating that clears the recap
 *          gate is T7's floating glass sheet, which floats over THIS scroll — the
 *          overlay seam is marked below.
 * Inputs: sessionId; a SessionFlowService (APIClient live; a fixture stub under
 *         the -startRecap screenshot hatch).
 * Outputs: none directly — "Open" dismisses the recap and pushes the case detail.
 * Run: presented by RootShell's recap fullScreenCover (keyed on
 *      AppRouter.recapSessionID); reached via AppRouter.go(to: .recap(id)).
 */

import SwiftUI

struct RecapReportView: View {
    let sessionId: Int
    let flowService: SessionFlowService

    @State private var model: RecapViewModel
    @Environment(\.dsPalette) private var palette
    // MARK: - F5-T7 close-out sheet state (the gate). The sheet floats in the
    // overlay seam below; its unlock rides `scrollMetrics` off the report scroll,
    // latched by `everUnlocked` so it stays open once the report is read.
    @State private var closeOut: RecapCloseOutViewModel
    @State private var scrollMetrics = RecapScrollMetrics()
    @State private var everUnlocked = false
    #if DEBUG
    @State private var scrollToTailForShot = false  // -startRecap shot only
    #endif

    init(sessionId: Int, flowService: SessionFlowService = APIClient.shared) {
        self.sessionId = sessionId
        self.flowService = flowService
        _model = State(initialValue: RecapViewModel(sessionId: sessionId, flow: flowService))
        _closeOut = State(initialValue: RecapCloseOutViewModel(sessionId: sessionId, flow: flowService))
    }

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                header
                scrollBody
            }
        }
        // LIGHT — the recap is a post-session report, presented in daylight over
        // the shell (RootShell's recap cover deliberately does NOT theme .dark).
        // The explicit .light guards the subtree if it is ever nested under a
        // dark seam, exactly like DebriefView's dark→light return point.
        .dsTheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        // MARK: - F5-T7 close-out seam. The floating glass "RATE THIS CASE 1–5"
        // close-out sheet floats HERE, over the scroll. The scroll body reserves
        // 250pt of bottom padding so the sheet never occludes the ATTACHED row; it
        // unlocks at scrollBottom − 16 (RecapCloseOutPresentation, fed by
        // `scrollMetrics`) and clears the gate via flowService.recapClose.
        .overlay(alignment: .bottom) {
            RecapCloseOutSheet(
                model: closeOut,
                unlocked: sheetUnlocked,
                progress: sheetProgress,
                interviewerName: model.interviewerName,
                onCleared: { AppRouter.shared.recapSessionID = nil }
            )
        }
        // "Gate cleared." rises over the report on close, then the cover dismisses.
        .dsToast(item: Binding(get: { closeOut.toast }, set: { closeOut.toast = $0 }))
        .task {
            await model.onAppear()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-startRecap") {
                try? await Task.sleep(nanoseconds: 500_000_000)  // let the report lay out
                let mode = Self.debugCloseOutMode()
                // locked keeps the report near the top; unlocked/cleared scroll the
                // report's end into frame behind the (forced-open) sheet.
                if mode != "locked" { scrollToTailForShot = true }
                switch mode {
                case "unlocked":
                    closeOut.rating = 4                     // Close enabled
                case "cleared":
                    closeOut.rating = 4
                    closeOut.cleared = true
                    closeOut.toast = "Gate cleared."        // held for the shot (no dismiss)
                default:
                    break
                }
            }
            #endif
        }
    }

    // MARK: - Header (canvas 6b masthead bar)

    private var header: some View {
        HStack {
            Text("RECAP — REQUIRED READING")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.green)
            Spacer()
            if let date = model.dateKicker {
                Text(date)
                    .font(.archivo(9, weight: 600))
                    .tracking(9 * 0.12)
                    .foregroundStyle(palette.faint)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { hairline(palette.hairline) }
    }

    // MARK: - Scroll body

    private var scrollBody: some View {
        // GeometryReader captures the scroll viewport height; the inner probe
        // reports the content's live offset + height (F5-T7 unlock at bottom − 16).
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.report != nil {
                            report
                        } else if model.loaded {
                            unavailable
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                        }
                        // Tail anchor (above the reserved bottom padding) so the
                        // -startRecap shot can scroll the ATTACHED row into frame.
                        Color.clear.frame(height: 1).id(Self.tailAnchor)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    // Generous bottom padding reserves room for T7's floating close-out
                    // sheet so the last content row is never hidden behind it (canvas 6b:
                    // the scroll pads 250px at the bottom for the sheet).
                    .padding(.bottom, 250)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // MARK: - F5-T7 scroll probe. Reports the report's live offset +
                    // content height so the close-out sheet unlocks at bottom − 16.
                    .background(scrollProbe)
                }
                .coordinateSpace(name: Self.scrollSpace)
                #if DEBUG
                // Screenshot-only: -startRecap scrolls to the tail so the ATTACHED row
                // is captured (the report is taller than one screen). Inert otherwise.
                .onChange(of: scrollToTailForShot) { _, on in
                    if on { proxy.scrollTo(Self.tailAnchor, anchor: .bottom) }
                }
                #endif
            }
            .onPreferenceChange(RecapScrollKey.self) { sample in
                guard sample.contentHeight > 0 else { return }
                scrollMetrics.offset = sample.offset
                scrollMetrics.contentHeight = sample.contentHeight
                updateUnlockLatch()
            }
            .onAppear {
                scrollMetrics.viewportHeight = viewport.size.height
                updateUnlockLatch()
            }
            .onChange(of: viewport.size.height) { _, height in
                scrollMetrics.viewportHeight = height
                updateUnlockLatch()
            }
        }
    }

    // MARK: - F5-T7 close-out unlock (bottom − 16) + progress

    private var scrollProbe: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: RecapScrollKey.self,
                value: RecapScrollSample(
                    offset: -geo.frame(in: .named(Self.scrollSpace)).minY,
                    contentHeight: geo.size.height))
        }
    }

    /// Latch the unlock once the report reaches bottom − 16, so the close-out
    /// stays open even if the reader scrolls back up.
    private func updateUnlockLatch() {
        guard !everUnlocked else { return }
        if RecapCloseOutPresentation.isUnlocked(
            offset: scrollMetrics.offset,
            contentHeight: scrollMetrics.contentHeight,
            viewportHeight: scrollMetrics.viewportHeight) {
            withAnimation(DSMotion.sheetCurve) { everUnlocked = true }
        }
    }

    private var sheetUnlocked: Bool {
        #if DEBUG
        if let mode = Self.debugCloseOutMode() { return mode != "locked" }
        #endif
        return everUnlocked
    }

    private var sheetProgress: Double {
        #if DEBUG
        if Self.debugCloseOutMode() == "locked" { return 0.62 }
        #endif
        return RecapCloseOutPresentation.scrollProgress(
            offset: scrollMetrics.offset,
            contentHeight: scrollMetrics.contentHeight,
            viewportHeight: scrollMetrics.viewportHeight)
    }

    #if DEBUG
    // The -startRecap sub-arg selecting the close-out screenshot state
    // (locked / unlocked / cleared); nil = the plain T6 report shot.
    static func debugCloseOutMode() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startRecap"), i + 1 < args.count else { return nil }
        let next = args[i + 1]
        return ["locked", "unlocked", "cleared"].contains(next) ? next : nil
    }
    #endif

    private static let tailAnchor = "recap-tail"
    private static let scrollSpace = "recap-scroll"

    // MARK: - Report content

    @ViewBuilder
    private var report: some View {
        // Masthead: case title + interviewer attribution.
        Text(model.caseTitle)
            .font(.archivo(24, weight: 800))
            .tracking(-0.72)
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 4)
        Text(model.subline)
            .font(.archivo(12, weight: 400))
            .foregroundStyle(palette.muted)
            .padding(.bottom, 16)

        // Rubric bars (points/max, tabular values — canvas 7/5/8/6).
        VStack(spacing: 8) {
            ForEach(model.items) { item in
                RecapBarRow(label: item.label, points: item.points, max: item.maxPoints)
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) { hairline(palette.hairline) }
        .padding(.bottom, 16)

        // Serif prose — notes_md paragraphs, then any per-item notes.
        VStack(alignment: .leading, spacing: 12) {
            Text(RecapPresentation.feedbackHeading(model.interviewerName))
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, -2)

            ForEach(Array(model.paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .dsText(.serif(14.5))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Per-item feedback lines, where the interviewer scored a note. Each
            // is a small dimension kicker over its serif line (empty when the
            // report's notes all live in notes_md, as in canvas 6b).
            ForEach(Array(model.itemNotes.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.label.uppercased())
                        .font(.archivo(9, weight: 600))
                        .tracking(9 * 0.14)
                        .foregroundStyle(palette.faint)
                    Text(entry.note)
                        .dsText(.serif(13.5))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .overlay(alignment: .top) { hairline(palette.ink) }
        .padding(.bottom, 16)

        // Attached case-pack PDF row (Library striped-thumb look, replicated).
        attachedRow
            .padding(.top, 12)
            .overlay(alignment: .top) { hairline(palette.hairline) }
    }

    // MARK: - Attached PDF row

    private var attachedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATTACHED")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
            HStack(spacing: 14) {
                RecapStripedThumb(size: CGSize(width: 38, height: 48))
                Text("Full case PDF")
                    .font(.archivo(13, weight: 600))
                    .foregroundStyle(palette.ink)
                Spacer()
                Button {
                    // No recap PDF endpoint — "Open" dismisses the recap and pushes
                    // the case detail (which owns the real case-pack PDF affordance).
                    AppRouter.shared.recapSessionID = nil
                    if let caseId = model.caseId {
                        AppRouter.shared.go(to: .caseDetail(caseId))
                    }
                }
                label: {
                    Text("Open")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.ink)
                        .underline(true, pattern: .solid)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty / error state

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.caseTitle)
                .dsText(.takeoverDisplay)
                .foregroundStyle(palette.ink)
            Text("This recap isn't ready to read yet. It lands here the moment your interviewer finalizes the feedback.")
                .dsText(.serif(14, italic: true))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hairline(_ color: Color) -> some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: - Rubric bar row (label · ink track · tabular value — canvas 6b grid)

private struct RecapBarRow: View {
    let label: String
    let points: Int
    let max: Int
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.archivo(11.5, weight: 600))
                .foregroundStyle(palette.ink)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.ink.opacity(0.10))
                    Rectangle().fill(palette.ink)
                        .frame(width: geo.size.width * RecapPresentation.barFraction(points: points, max: max))
                }
            }
            .frame(height: 2)
            Text("\(points)")
                .font(.archivo(11, weight: 600))
                .tabularNumbers()
                .foregroundStyle(palette.muted)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Striped case-pack thumb (Library CaseDetailContent.StripedThumb look,
// replicated so this screen never depends on F4's private view — 6px bands
// alternating onInk/surface, hairline border).

private struct RecapStripedThumb: View {
    let size: CGSize
    @Environment(\.dsPalette) private var palette

    var body: some View {
        Canvas { context, canvasSize in
            let bandHeight: CGFloat = 6
            var y: CGFloat = 0
            var isOnInk = true
            while y < canvasSize.height {
                let band = CGRect(x: 0, y: y, width: canvasSize.width, height: bandHeight)
                context.fill(Path(band), with: .color(isOnInk ? palette.onInk : palette.surface))
                y += bandHeight
                isOnInk.toggle()
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    NavigationStack { SessionFixtures.recapStandalone() }
}
#endif
