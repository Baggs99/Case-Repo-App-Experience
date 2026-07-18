/*
 * Purpose: Debrief screen (F5 Task 5) — the dark→LIGHT return point. The session
 *          takeover is dark (lobby/negotiation/live, seamed by RootShell's
 *          fullScreenCover); the debrief re-overrides to the LIGHT palette at
 *          this view's root, back to daylight for the recap.
 *          Candidate: once feedback is released — the 7.2 avg, the rubric bars
 *          (from the report's items points/max), the serif feedback line, and
 *          the REQUIRED 1–5 rating (interactive ScoreCells → recapClose, which
 *          clears the gate); then Schedule-next (prefilled to the interviewer)
 *          and Close-logged. Before release: a "waiting for feedback" state.
 *          Interviewer: the grade-preview / override / Finalize flow restyled
 *          onto tokens, plus "Swap roles → invite sent" (swap).
 * Inputs: SessionViewModel (role/finalized/releasedGrade/interviewerId + the
 *         finalize action); RubricViewModel (interviewer grade preview);
 *         SessionFlowService (feedbackReport / recapClose / swap).
 * Outputs: none directly — Finalize routes through SessionViewModel.finalize;
 *          Schedule-next / Close route through AppRouter (existing nav).
 * Run: shown by SessionView while state is "debrief" (and, for the candidate,
 *      "finalized" — the released grade lands there).
 */

import SwiftUI

struct DebriefView: View {
    var sessionViewModel: SessionViewModel
    var rubricViewModel: RubricViewModel?
    let flowService: SessionFlowService

    @State private var model: DebriefViewModel
    @State private var overrideText: String = ""

    init(sessionViewModel: SessionViewModel, rubricViewModel: RubricViewModel? = nil,
         flowService: SessionFlowService) {
        self.sessionViewModel = sessionViewModel
        self.rubricViewModel = rubricViewModel
        self.flowService = flowService
        _model = State(initialValue: DebriefViewModel(sessionId: sessionViewModel.sessionId, flow: flowService))
    }

    var body: some View {
        Group {
            if sessionViewModel.role == "interviewer" {
                InterviewerDebriefContent(
                    model: model, sessionViewModel: sessionViewModel,
                    rubricViewModel: rubricViewModel, overrideText: $overrideText)
            } else {
                CandidateDebriefContent(model: model, sessionViewModel: sessionViewModel)
            }
        }
        // MARK: - F5-T5 — dark→light return point. The debrief renders INSIDE
        // RootShell's dark takeover fullScreenCover; this override re-themes the
        // subtree to LIGHT so DSBackground/glass/ScoreCells/tokens all re-read
        // \.dsPalette and go daylight. Applied at the DebriefView root so it wins
        // over the inherited .dark seam (the known light-in-dark risk). Every
        // palette read below sits in a CHILD view, under this modifier, so none
        // resolve to the inherited dark value.
        .dsTheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: sessionViewModel.state) {
            if sessionViewModel.role == "interviewer" {
                await rubricViewModel?.load()
            } else {
                await model.loadReport()
            }
        }
    }
}

// MARK: - Candidate debrief (canvas 4a debrief)

private struct CandidateDebriefContent: View {
    var model: DebriefViewModel
    var sessionViewModel: SessionViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack {
            DSBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    debriefPill.padding(.bottom, 22)

                    if model.released, let report = model.report {
                        released(report)
                    } else if model.loaded {
                        waiting
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var debriefPill: some View {
        HStack(spacing: 7) {
            Text("DEBRIEF").dsText(.kicker).foregroundStyle(palette.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassChip()
    }

    // MARK: released

    @ViewBuilder
    private func released(_ report: FeedbackReport) -> some View {
        // Average — the finalized grade, big + tabular (canvas 52px/800).
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(DebriefPresentation.avgText(report.grade))
                .font(.archivo(52, weight: 800))
                .tracking(-1.56)
                .tabularNumbers()
                .foregroundStyle(palette.ink)
            Text(DebriefPresentation.dimensionsLabel(count: report.items.count))
                .font(.archivo(10, weight: 600))
                .tracking(10 * 0.12)
                .foregroundStyle(palette.muted)
        }
        .padding(.bottom, 14)

        // Rubric bars (from items points/max).
        VStack(spacing: 8) {
            ForEach(report.items) { item in
                BarRow(label: item.label, points: item.points, max: item.maxPoints)
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) { hairline(palette.hairline) }
        .padding(.bottom, 14)

        // Serif feedback line (notes_md) + attribution.
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(report.notesMd)”")
                .dsText(.serif(15, italic: true))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(attribution)
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.14)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .overlay(alignment: .top) { hairline(palette.ink) }
        .padding(.bottom, 16)

        ratingBlock
            .padding(.top, 13)
            .overlay(alignment: .top) { hairline(palette.hairline) }
            .padding(.bottom, 18)

        actions
    }

    private var attribution: String {
        (sessionViewModel.interviewerName ?? "Your interviewer").uppercased()
    }

    // MARK: required 1–5 rating

    @ViewBuilder
    private var ratingBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("RATE THIS CASE — REQUIRED")
                    .font(.archivo(9.5, weight: 600))
                    .tracking(9.5 * 0.15)
                    .foregroundStyle(palette.ink)
                Spacer()
                if model.gateCleared {
                    Text("RECAP CLEARED")
                        .font(.archivo(9, weight: 600))
                        .tracking(9 * 0.12)
                        .foregroundStyle(palette.green)
                }
            }
            // SHARED ScoreCells (F0). Interactive until cleared; then a
            // non-interactive confirmed strip (the chosen value stays filled).
            ScoreCells(
                count: 5, value: model.rating, size: .large,
                interactive: !model.gateCleared,
                onSelect: { n in Task { await model.rate(n) } }
            )
            if let rateError = model.rateError {
                Text(rateError)
                    .dsText(.serif(12, italic: true))
                    .foregroundStyle(palette.muted)
            }
        }
    }

    // MARK: actions (candidate — swap OMITTED per DV-B3-SWAP)

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            DebriefButtons.primary("Schedule your next session", palette: palette) {
                if let toUser = sessionViewModel.interviewerId {
                    AppRouter.shared.proposeToUserID = toUser
                }
                AppRouter.shared.sessionTakeoverID = nil   // dismiss the takeover
            }
            DebriefButtons.underline("Close — logged to History", palette: palette) {
                AppRouter.shared.sessionTakeoverID = nil
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: waiting (pre-release)

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vs \(sessionViewModel.interviewerName ?? "your interviewer")")
                .dsText(.takeoverDisplay)
                .foregroundStyle(palette.ink)
            Text("Waiting for feedback. Your recap — the grade, the rubric, and the note — lands here the moment it's finalized.")
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

// MARK: - Interviewer debrief (grade preview / override / Finalize + Swap)

private struct InterviewerDebriefContent: View {
    var model: DebriefViewModel
    var sessionViewModel: SessionViewModel
    var rubricViewModel: RubricViewModel?
    @Binding var overrideText: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack {
            DSBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pill.padding(.bottom, 22)

                    Text("GRADE PREVIEW")
                        .font(.archivo(9.5, weight: 600))
                        .tracking(9.5 * 0.15)
                        .foregroundStyle(palette.muted)
                        .padding(.bottom, 8)
                    Text(DebriefPresentation.avgText(rubricViewModel?.gradePreview))
                        .font(.archivo(52, weight: 800))
                        .tracking(-1.56)
                        .tabularNumbers()
                        .foregroundStyle(palette.ink)
                        .padding(.bottom, 18)

                    overrideBlock
                        .padding(.top, 13)
                        .overlay(alignment: .top) { hairline(palette.hairline) }
                        .padding(.bottom, 20)

                    DebriefButtons.primary(
                        "Finalize", palette: palette, disabled: sessionViewModel.finalized
                    ) {
                        await sessionViewModel.finalize(grade: Double(overrideText))
                    }
                    .padding(.bottom, 12)

                    swapAction
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pill: some View {
        Text("DEBRIEF · INTERVIEWER")
            .dsText(.kicker)
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassChip()
    }

    private var overrideBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("OVERRIDE GRADE — OPTIONAL")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.ink)
            TextField("Leave blank to use the preview", text: $overrideText)
                .font(.archivo(14, weight: 600))
                .tabularNumbers()
                .keyboardType(.decimalPad)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassKey()
        }
    }

    @ViewBuilder
    private var swapAction: some View {
        // DV-B3-SWAP: interviewer-only. On success → verbatim "invite sent".
        if model.swapSent {
            Text("invite sent")
                .dsText(.serif(13, italic: true))
                .foregroundStyle(palette.green)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            DebriefButtons.underline("Swap roles", palette: palette) {
                await model.initiateSwap()
            }
            .frame(maxWidth: .infinity)
        }
        if let swapError = model.swapError {
            Text(swapError)
                .dsText(.serif(12, italic: true))
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
    }

    private func hairline(_ color: Color) -> some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: - Rubric bar row (label · ink track · tabular value)

private struct BarRow: View {
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
                        .frame(width: geo.size.width * DebriefPresentation.barFraction(points: points, max: max))
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

// MARK: - Shared debrief buttons (match the takeover: ink capsule / underline)

private enum DebriefButtons {
    static func primary(_ title: String, palette: DSPalette, disabled: Bool = false,
                        action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(14, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(palette.ink.opacity(disabled ? 0.4 : 1)))
        }
        .buttonStyle(DSPressStyle())
        .disabled(disabled)
    }

    static func underline(_ title: String, palette: DSPalette,
                          action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(12.5, weight: 600))
                .foregroundStyle(palette.muted)
                .underline(true, pattern: .solid)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Candidate") {
    NavigationStack {
        SessionFixtures.debriefCandidateStandalone()
    }
    .dsTheme(.dark)
}

#Preview("Interviewer") {
    NavigationStack {
        SessionFixtures.debriefInterviewerStandalone()
    }
    .dsTheme(.dark)
}
