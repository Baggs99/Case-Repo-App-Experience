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

    init(sessionId: Int, flowService: SessionFlowService = APIClient.shared) {
        self.sessionId = sessionId
        self.flowService = flowService
        _model = State(initialValue: RecapViewModel(sessionId: sessionId, flow: flowService))
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
        // MARK: - F5-T7 close-out seam. T7 floats its glass "RATE THIS CASE 1–5"
        // close-out sheet HERE, as an .overlay(alignment: .bottom) over this
        // scroll. The scroll body already reserves 250pt of bottom padding so the
        // floating sheet never occludes the ATTACHED row; T7 drives the unlock
        // threshold (scrollBottom − 16) off its own scroll listener and clears the
        // gate via flowService.recapClose. This placeholder documents the seam.
        .overlay(alignment: .bottom) { EmptyView() /* T7: close-out sheet */ }
        .task { await model.onAppear() }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.report != nil {
                    report
                } else if model.loaded {
                    unavailable
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            // Generous bottom padding reserves room for T7's floating close-out
            // sheet so the last content row is never hidden behind it (canvas 6b:
            // the scroll pads 250px at the bottom for the sheet).
            .padding(.bottom, 250)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full case PDF")
                        .font(.archivo(13, weight: 600))
                        .foregroundStyle(palette.ink)
                    Text("The pack you cased from")
                        .font(.archivo(11, weight: 400))
                        .foregroundStyle(palette.muted)
                }
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
