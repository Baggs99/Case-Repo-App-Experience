/*
 * Purpose: The interviewer's live console (F6, canvas 8b phone / 1a tablet). The
 *          console IS the interviewer's live seat (A1) — SessionView repoints its
 *          `live` interviewer branch here, at the `liveContent` level, so it
 *          renders WITHOUT the outer VideoCallView wrapper (the console owns its
 *          own media surface). Overrides to the LIGHT palette at its root
 *          (`.dsTheme(.light)`, exactly like DebriefView returns to daylight
 *          inside the dark takeover cover). Wraps the shared RubricViewModel via a
 *          ConsoleViewModel (stage nav, view-local clocks, exhibit release/recall,
 *          toggle-clear scoring) — every state-changing action flows through the
 *          existing plumbing (A2). Transport/crypto/signaling untouched.
 * Inputs: the shared RubricViewModel (SessionView entry) OR a pre-seeded
 *         ConsoleViewModel (screenshot fixtures), plus the header kicker/title.
 * Outputs: none directly — scoring/reveal/finalize forward through the VM.
 * Run: shown by SessionView while state == "live" for the interviewer; the shot
 *      fixtures render it directly under `-startTakeover console-phone[-scored]`.
 *
 * THIS TASK (T2) ships the phone (.compact) layout in full and renders it for
 * .regular too as an interim; T3 replaces the .regular branch with the tablet
 * hero (see the `// T3: tablet hero` marker below).
 */

import SwiftUI

struct InterviewerConsoleView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var model: ConsoleViewModel
    let caseKicker: String
    let caseTitle: String

    // Drives the view-local clocks (A6): tick() advances only the running clocks.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// SessionView entry — builds the phone console VM from the shared rubric.
    init(rubric: RubricViewModel, caseKicker: String, caseTitle: String) {
        _model = State(initialValue: ConsoleViewModel(stages: ConsoleScript.phone, isPhone: true, rubric: rubric))
        self.caseKicker = caseKicker
        self.caseTitle = caseTitle
    }

    /// Fixture/standalone entry — accepts a pre-seeded model (clock running,
    /// scores, a released exhibit) so the shot isn't a cold 0:00 frame (rv #8).
    init(model: ConsoleViewModel, caseKicker: String, caseTitle: String) {
        _model = State(initialValue: model)
        self.caseKicker = caseKicker
        self.caseTitle = caseTitle
    }

    var body: some View {
        content
            // A1 — the console overrides to the LIGHT palette at its root, so
            // every palette read in the CHILD PhoneConsole re-resolves to light
            // even under RootShell's dark takeover cover (the DebriefView pattern).
            .dsTheme(.light)
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.rubric.load() }
            .onReceive(ticker) { _ in model.tick() }
    }

    @ViewBuilder
    private var content: some View {
        // Size-class aware (A1, CaseTabLayout.isTablet pattern). Both branches
        // render the phone layout in T2; T3 swaps the .regular branch for the
        // tablet hero (canvas 1a).
        if CaseTabLayout.isTablet(hSize) {
            // T3: tablet hero — interim phone layout for .regular until T3 lands.
            PhoneConsole(model: model, caseKicker: caseKicker, caseTitle: caseTitle)
        } else {
            // Phone (.compact) — the shipped canvas 8b layout.
            PhoneConsole(model: model, caseKicker: caseKicker, caseTitle: caseTitle)
        }
    }
}

// MARK: - Phone console (canvas 8b)

/// The phone console body. A child view so every `\.dsPalette` read below sits
/// UNDER InterviewerConsoleView's `.dsTheme(.light)` and resolves to light.
private struct PhoneConsole: View {
    let model: ConsoleViewModel
    let caseKicker: String
    let caseTitle: String
    @Environment(\.dsPalette) private var palette

    private var stage: ConsoleStage { model.currentStage }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.page.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                stageChipRow
                ScrollView {
                    stageBody
                }
                .scrollIndicators(.hidden)
            }

            bottomBar
        }
        .overlay { if model.isPDFOpen { pdfPlaceholder } }   // T5 stub (no crash)
    }

    // MARK: Header (kicker + title + tap-to-run clock pill)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caseKicker)
                    .font(.archivo(8.5, weight: 600)).tracking(8.5 * 0.14)
                    .foregroundStyle(palette.muted)
                Text(caseTitle)
                    .font(.archivo(14, weight: 700)).tracking(-0.14)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 10)
            clockPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var clockPill: some View {
        Button { model.toggleMaster() } label: {
            HStack(spacing: 8) {
                if model.isMasterRunning {
                    BlinkDot(diameter: 6)
                } else {
                    Circle().fill(palette.faint).frame(width: 6, height: 6)
                }
                Text(model.mmss)
                    .font(.archivo(14, weight: 800)).tabularNumbers()
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .glassChipFlat()
        }
        .buttonStyle(DSPressStyle())
    }

    // MARK: Stage chip row (border-bottom rail)

    private var stageChipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(model.stages.enumerated()), id: \.offset) { i, s in
                    stageChip(index: i, stage: s)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func stageChip(index: Int, stage s: ConsoleStage) -> some View {
        let active = index == model.stageIndex
        return Button { model.pickStage(index) } label: {
            HStack(spacing: 5) {
                Text("\(index + 1)").tabularNumbers()
                Text(s.name)
            }
            .font(.archivo(10, weight: 600)).tracking(10 * 0.08)
            .foregroundStyle(active ? palette.onInk : palette.ink)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background {
                if active {
                    Capsule().fill(palette.ink)
                } else {
                    Capsule().fill(palette.surface)
                        .overlay(Capsule().strokeBorder(palette.hairline, lineWidth: 1))
                }
            }
        }
        .buttonStyle(DSPressStyle())
    }

    // MARK: Stage body (read-aloud + exhibits + guidance + score)

    private var stageBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STAGE \(model.stageIndex + 1) OF 06 — READ ALOUD")
                .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                .foregroundStyle(palette.green)
                .padding(.bottom, 8)

            Text(stage.readAloud)
                .font(.serifVoice(16.5)).lineSpacing(16.5 * 0.55)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            exhibitRows
            guidanceBlock
            scoreBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 120)   // clears the floating bottom bar
    }

    @ViewBuilder
    private var exhibitRows: some View {
        if !stage.exhibitRefs.isEmpty {
            VStack(spacing: 7) {
                ForEach(Array(stage.exhibitRefs.enumerated()), id: \.offset) { j, ref in
                    exhibitRow(index: j, ref: ref)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func exhibitRow(index: Int, ref: ConsoleExhibitRef) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXHIBIT \(String(format: "%02d", index + 1))")
                    .font(.archivo(8.5, weight: 600)).tracking(8.5 * 0.14)
                    .foregroundStyle(palette.muted)
                Text(ref.label)
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if let sent = model.sentAt(scriptId: ref.scriptId) {
                Text("SENT · \(sent)")
                    .font(.archivo(9, weight: 600)).tracking(9 * 0.1).tabularNumbers()
                    .foregroundStyle(palette.green)
                Button { model.recall(scriptId: ref.scriptId) } label: {
                    Text("Recall")
                        .font(.archivo(11, weight: 600))
                        .foregroundStyle(palette.muted)
                        .underline(true, pattern: .solid)
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await model.release(scriptId: ref.scriptId) } } label: {
                    Text("Release")
                        .font(.archivo(11, weight: 600))
                        .foregroundStyle(palette.onInk)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(palette.ink))
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(palette.surface)
        .overlay(Rectangle().strokeBorder(palette.hairline, lineWidth: 1))   // square corners
    }

    private var guidanceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GUIDANCE — NOT READ ALOUD")
                .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            ForEach(Array(stage.guidance.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Text("—").foregroundStyle(palette.faint).frame(width: 16, alignment: .leading)
                    Text(line)
                        .font(.archivo(13)).lineSpacing(13 * 0.5)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.top, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var scoreBlock: some View {
        // Phone is 1:1 — the stage's single mapped dim (CLARIFY carries none → the
        // whole block is hidden). Scale + readout derive from item.maxPoints (A3).
        if let item = model.stageItems(model.rubric.templateItems).first {
            let name = ConsoleScript.dims[item.id]?.name ?? item.label
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SCORE — \(name)")
                        .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                        .foregroundStyle(palette.green)
                    Spacer()
                    Text("\(model.points(dimId: item.id)) / \(item.maxPoints)")
                        .font(.archivo(9, weight: 600)).tracking(9 * 0.1).tabularNumbers()
                        .foregroundStyle(palette.faint)
                }
                .padding(.bottom, 8)

                ScoreCells(
                    count: item.maxPoints,
                    value: model.points(dimId: item.id),
                    size: .medium,
                    interactive: true
                ) { model.score(dimId: item.id, points: $0) }
                .padding(.bottom, 10)

                TextField(
                    "Evidence — quotes, moments, misses",
                    text: Binding(
                        get: { model.note(dimId: item.id) },
                        set: { model.setNote(dimId: item.id, note: $0) })
                )
                .textFieldStyle(.plain)
                .font(.serifVoice(13, italic: true))
                .foregroundStyle(palette.ink)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline).frame(height: 1) }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }   // 2px ink top rule
        }
    }

    // MARK: Bottom floating glass bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button { model.prevStage() } label: {
                Text("Previous")
                    .font(.archivo(12, weight: 600))
                    .foregroundStyle(palette.muted)
                    .underline(true, pattern: .solid)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            Button { model.openPDF() } label: {   // T5 — opens the phone PDF pager
                Text("Display PDF")
                    .font(.archivo(11, weight: 600))
                    .foregroundStyle(palette.ink)
                    .underline(true, pattern: .solid)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                if model.isLastStage {
                    Task { await model.finalizeAndSend() }
                } else {
                    model.nextStage()
                }
            } label: {
                Text(model.isLastStage ? "Finalize & send" : "Next stage")
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(Capsule().fill(palette.ink))
            }
            .buttonStyle(DSPressStyle())
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .glassChip()
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: PDF placeholder (T5 stub — no-op-graceful until the pager lands)

    private var pdfPlaceholder: some View {
        ZStack {
            palette.page.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("CASE PACK — INTERVIEWER COPY · 8 PAGES")
                    .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                Text("The script keeps scoring; this is the paper.")
                    .dsText(.serif(14, italic: true))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                Button { model.closePDF() } label: {
                    Text("‹ Back to script")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.ink)
                        .underline(true, pattern: .solid)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
}
