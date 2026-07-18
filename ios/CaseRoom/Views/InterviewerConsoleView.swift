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
 * T2 shipped the phone (.compact) layout. T3 lands the tablet hero (canvas 1a)
 * for .regular — chrome (top bar + cap bar) + the LEFT pane (script/exhibits/
 * SCORE THIS STAGE/footer); the RIGHT rail is a placeholder here (T4 fills it).
 * The VM chooses its script/mode by size class: `.regular` drives the 7-stage
 * tablet script (union dim resolution), `.compact` the 6-stage phone subset.
 */

import SwiftUI

struct InterviewerConsoleView: View {
    @State private var model: ConsoleViewModel
    let caseKicker: String
    let caseTitle: String
    /// The candidate's name for the tablet top bar's CANDIDATE block (canvas 1a
    /// "Amara Osei · Wharton MBA"). Empty on the phone / when unknown → the block
    /// is hidden.
    let candidateName: String
    /// Whether to render the tablet hero (canvas 1a) vs the phone console (8b).
    /// Stored (not re-read from the size class) so the rendered layout always
    /// matches the VM's script/resolution mode chosen at init.
    private let isTablet: Bool

    // Drives the view-local clocks (A6): tick() advances only the running clocks.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// SessionView entry — builds the console VM from the shared rubric. The size
    /// class picks the script + resolution mode: tablet (7-stage union) on
    /// `.regular`, phone (6-stage 1:1) on `.compact`.
    init(rubric: RubricViewModel, caseKicker: String, caseTitle: String,
         candidateName: String = "", isTablet: Bool = false) {
        let stages = isTablet ? ConsoleScript.tablet : ConsoleScript.phone
        _model = State(initialValue: ConsoleViewModel(stages: stages, isPhone: !isTablet, rubric: rubric))
        self.caseKicker = caseKicker
        self.caseTitle = caseTitle
        self.candidateName = candidateName
        self.isTablet = isTablet
    }

    /// Fixture/standalone entry — accepts a pre-seeded model (clock running,
    /// scores, a released exhibit) so the shot isn't a cold 0:00 frame (rv #8).
    /// The layout follows the model's mode (`isPhone`).
    init(model: ConsoleViewModel, caseKicker: String, caseTitle: String, candidateName: String = "") {
        _model = State(initialValue: model)
        self.caseKicker = caseKicker
        self.caseTitle = caseTitle
        self.candidateName = candidateName
        self.isTablet = !model.isPhone
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
        // Dispatch on the stored flag (set from the size class at the SessionView
        // seam, A1) so the rendered layout always matches the VM's script.
        if isTablet {
            // Tablet hero — canvas 1a chrome + LEFT pane (T3); RIGHT rail = T4 stub.
            TabletConsole(model: model, caseKicker: caseKicker, caseTitle: caseTitle,
                          candidateName: candidateName)
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
            Text("STAGE \(model.stageIndex + 1) OF \(String(format: "%02d", model.stages.count)) — READ ALOUD")
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

// MARK: - Tablet console (canvas 1a) — chrome + LEFT pane

/// The tablet hero body (canvas 1a). A child view so every `\.dsPalette` read
/// resolves to light under InterviewerConsoleView's `.dsTheme(.light)`. Ships the
/// chrome (top bar + 2px cap bar) and the LEFT pane (stage chips, READ ALOUD,
/// exhibit rows, GUIDANCE, SCORE THIS STAGE, footer); the RIGHT rail is a
/// placeholder (T4 builds the feed / segment timer / rubric rail).
private struct TabletConsole: View {
    let model: ConsoleViewModel
    let caseKicker: String
    let caseTitle: String
    let candidateName: String
    @Environment(\.dsPalette) private var palette

    private var stage: ConsoleStage { model.currentStage }
    /// "OF %02d" derives from the loaded script (7 tablet stages → "07"), never
    /// a hardcoded count.
    private var stageCountLabel: String { String(format: "%02d", model.stages.count) }
    /// The dims this stage scores (union + catch-all, A4).
    private var stageDims: [RubricTemplateItem] { model.stageItems(model.rubric.templateItems) }

    var body: some View {
        ZStack {
            palette.page.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                capBar
                bodyGrid
            }
        }
        .overlay { if model.isPDFOpen { pdfPlaceholder } }   // T5 stub (no crash)
    }

    // MARK: Top bar (mark + wordmark | CASE | CANDIDATE | clock | Finalize)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            StaircaseMarkView().frame(width: 22, height: 18)
            (Text("my").font(.serifVoice(15, italic: true))
             + Text("Case").font(.archivo(15, weight: 800)).tracking(-0.3))
                .foregroundStyle(palette.ink)

            Rectangle().fill(palette.hairline).frame(width: 1, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(caseKicker)
                    .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                    .foregroundStyle(palette.muted).lineLimit(1)
                Text(caseTitle)
                    .font(.archivo(15, weight: 700)).tracking(-0.15)
                    .foregroundStyle(palette.ink).lineLimit(1)
            }

            Spacer(minLength: 16)

            if !candidateName.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CANDIDATE")
                        .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                        .foregroundStyle(palette.muted)
                    Text(candidateName)
                        .font(.archivo(13, weight: 600))
                        .foregroundStyle(palette.ink).lineLimit(1)
                }
            }

            clockChip
            finalizeButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var clockChip: some View {
        Button { model.toggleMaster() } label: {
            HStack(spacing: 9) {
                if model.isMasterRunning {
                    BlinkDot(diameter: 6)
                } else {
                    Circle().fill(palette.faint).frame(width: 6, height: 6)
                }
                Text(model.mmss)
                    .font(.archivo(17, weight: 800)).tabularNumbers()
                    .foregroundStyle(palette.ink)
                Text(model.nLeft)
                    .font(.archivo(9, weight: 600)).tracking(9 * 0.08).tabularNumbers()
                    .foregroundStyle(model.isUnderFiveMin ? palette.green : palette.faint)
            }
            .padding(.horizontal, 17)
            .frame(height: 44)
            .glassChipFlat()
        }
        .buttonStyle(DSPressStyle())
        .fixedSize()
    }

    private var finalizeButton: some View {
        Button { Task { await model.finalizeAndSend() } } label: {
            Text("Finalize & send")
                .font(.archivo(13, weight: 600))
                .foregroundStyle(palette.onInk)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(palette.ink))
        }
        .buttonStyle(DSPressStyle())
        .fixedSize()
    }

    // MARK: 2px cap-progress bar (hairline track + green fill = capFraction)

    private var capBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.hairline)
                Rectangle().fill(palette.green)
                    .frame(width: max(0, geo.size.width * model.capFraction))
                    .animation(.linear(duration: 0.9), value: model.capFraction)
            }
        }
        .frame(height: 2)
        .padding(.top, 12)
    }

    // MARK: Body grid — 1fr / 380px

    private var bodyGrid: some View {
        HStack(spacing: 0) {
            leftPane.frame(maxWidth: .infinity, maxHeight: .infinity)
            rightRailPlaceholder
        }
    }

    // MARK: LEFT pane

    private var leftPane: some View {
        VStack(spacing: 0) {
            stageChipRow
            ScrollView {
                stageBody
            }
            .scrollIndicators(.hidden)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // Stage chip row (border-bottom hairline; active ink-fill). The canvas wraps
    // the 7 chips (flex-wrap); a horizontal scroll is the size-robust analog —
    // all 7 sit on one row on the wide hero (landscape), scroll on a narrow width.
    private var stageChipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.stages.enumerated()), id: \.offset) { i, s in
                    stageChip(index: i, stage: s)
                }
            }
            .padding(.bottom, 11)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func stageChip(index: Int, stage s: ConsoleStage) -> some View {
        let active = index == model.stageIndex
        return Button { model.pickStage(index) } label: {
            HStack(spacing: 6) {
                Text(s.num).tabularNumbers().opacity(0.7)
                Text(s.name)
            }
            .lineLimit(1).fixedSize()
            .font(.archivo(10.5, weight: 600)).tracking(10.5 * 0.08)
            .foregroundStyle(active ? palette.onInk : palette.muted)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                if active {
                    Capsule().fill(palette.ink)
                } else {
                    Color.clear.glassChipFlat()
                }
            }
        }
        .buttonStyle(DSPressStyle())
    }

    // Scroll region: READ ALOUD + exhibits + GUIDANCE + SCORE THIS STAGE.
    private var stageBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STAGE \(stage.num) OF \(stageCountLabel) — READ ALOUD")
                .font(.archivo(10, weight: 600)).tracking(10 * 0.15)
                .foregroundStyle(palette.green)
                .padding(.bottom, 12)

            Text(stage.readAloud)
                .font(.serifVoice(19)).lineSpacing(19 * 0.55)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            exhibitRows
            guidanceBlock
            scoreBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var exhibitRows: some View {
        if !stage.exhibitRefs.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(stage.exhibitRefs.enumerated()), id: \.offset) { _, ref in
                    exhibitRow(ref: ref)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.bottom, 14)
        }
    }

    private func exhibitRow(ref: ConsoleExhibitRef) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXHIBIT \(String(format: "%02d", ref.idx + 1))")
                    .font(.archivo(9, weight: 600)).tracking(9 * 0.14)
                    .foregroundStyle(palette.muted)
                Text(ref.label)
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(palette.ink).lineLimit(1)
            }
            Spacer(minLength: 8)

            if let sent = model.sentAt(scriptId: ref.scriptId) {
                Text("SENT · \(sent)")
                    .font(.archivo(10, weight: 600)).tracking(10 * 0.1).tabularNumbers()
                    .foregroundStyle(palette.green)
                Button { model.recall(scriptId: ref.scriptId) } label: {
                    Text("Recall")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.muted)
                        .underline(true, pattern: .solid)
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await model.release(scriptId: ref.scriptId) } } label: {
                    Text("Release to candidate")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.onInk)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(palette.ink))
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(palette.surface)
        .overlay(Rectangle().strokeBorder(palette.hairline, lineWidth: 1))   // square corners
    }

    private var guidanceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GUIDANCE — NOT READ ALOUD")
                .font(.archivo(10, weight: 600)).tracking(10 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 8)
            ForEach(Array(stage.guidance.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("—").foregroundStyle(palette.faint).frame(width: 18, alignment: .leading)
                    Text(line)
                        .font(.archivo(13.5)).lineSpacing(13.5 * 0.55)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: 620, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var scoreBlock: some View {
        // Tablet stacks EVERY dim this stage scores (A4 union). Header scale +
        // per-dim readout derive from item.maxPoints (A3 — never a literal 10).
        if !stageDims.isEmpty {
            let maxPoints = stageDims.first?.maxPoints ?? 10
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SCORE THIS STAGE — 1 TO \(maxPoints)")
                        .font(.archivo(10, weight: 600)).tracking(10 * 0.15)
                        .foregroundStyle(palette.green)
                    Spacer(minLength: 12)
                    Text("Collects into the rubric rail →")
                        .font(.archivo(11))
                        .foregroundStyle(palette.faint)
                }
                .padding(.bottom, 4)

                ForEach(stageDims, id: \.id) { item in
                    scoreDim(item)
                }
            }
            .padding(.top, 11)
            .frame(maxWidth: 620, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }   // 2px ink top rule
        }
    }

    private func scoreDim(_ item: RubricTemplateItem) -> some View {
        let name = ConsoleScript.dims[item.id]?.name ?? item.label
        let desc = ConsoleScript.dims[item.id]?.desc
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name)
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                Text("\(model.points(dimId: item.id)) / \(item.maxPoints)")
                    .font(.archivo(11.5)).tabularNumbers()
                    .foregroundStyle(palette.muted)
            }
            if let desc {
                Text(desc)
                    .font(.archivo(11.5))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 2).padding(.bottom, 9)
            } else {
                Color.clear.frame(height: 9)
            }

            ScoreCells(
                count: item.maxPoints,
                value: model.points(dimId: item.id),
                size: .medium,
                interactive: true
            ) { model.score(dimId: item.id, points: $0) }
            .padding(.bottom, 9)

            TextField(
                "Evidence — quotes, moments, misses",
                text: Binding(
                    get: { model.note(dimId: item.id) },
                    set: { model.setNote(dimId: item.id, note: $0) })
            )
            .textFieldStyle(.plain)
            .font(.serifVoice(13, italic: true))
            .foregroundStyle(palette.ink)
            .padding(.bottom, 5)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    // Footer: Previous · Display PDF pill · Next stage / Finalize & send.
    private var footer: some View {
        HStack(spacing: 18) {
            Button { model.prevStage() } label: {
                Text("Previous")
                    .font(.archivo(13, weight: 600))
                    .foregroundStyle(palette.muted)
                    .underline(true, pattern: .solid)
            }
            .buttonStyle(.plain)

            Button { model.openPDF() } label: {   // T5 fills the real left-pane overlay
                Text("Display PDF — always here")
                    .font(.archivo(12, weight: 600))
                    .foregroundStyle(palette.ink)
                    .underline(true, pattern: .solid)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .glassChipFlat()
            }
            .buttonStyle(DSPressStyle())

            Spacer(minLength: 12)

            Button {
                if model.isLastStage {
                    Task { await model.finalizeAndSend() }
                } else {
                    model.nextStage()
                }
            } label: {
                Text(model.isLastStage ? "Finalize & send" : "Next stage")
                    .font(.archivo(13, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Capsule().fill(palette.ink))
            }
            .buttonStyle(DSPressStyle())
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    // MARK: RIGHT rail placeholder (T4 builds the real feed / timer / rubric)

    private var rightRailPlaceholder: some View {
        ZStack {
            Text("// T4 rail")
                .font(.archivo(11, weight: 600)).tracking(11 * 0.08)
                .foregroundStyle(palette.faint)
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(palette.hairline).frame(width: 1) }
    }

    // MARK: PDF placeholder (T5 stub — graceful back-to-script until the overlay lands)

    private var pdfPlaceholder: some View {
        ZStack {
            palette.page.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("CASE PACK — INTERVIEWER COPY · 8 PAGES")
                    .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                    .foregroundStyle(palette.muted)
                Text("The script keeps scoring; this is the paper.")
                    .dsText(.serif(14, italic: true))
                    .foregroundStyle(palette.muted)
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
