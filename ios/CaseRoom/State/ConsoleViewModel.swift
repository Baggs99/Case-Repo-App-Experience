/*
 * Purpose: The interviewer console's view-model (F6). Wraps the shared
 *          `RubricViewModel` (decision A2 — all state-changing work flows
 *          through the existing plumbing) and owns the console-local state the
 *          canvas keeps client-side: stage navigation, the master + segment
 *          clocks (A6, view-local), exhibit release timestamps (A5, recall is a
 *          local un-mark), PDF pager, toggle-clear scoring, and the stage→
 *          template-item resolution (A4, two modes: tablet union+catch-all /
 *          phone 1:1). No transport, no timers of its own — the view drives the
 *          tick; `finalizeAndSend()` is the single finalize path (→ moveToDebrief).
 * Inputs: the chosen script (`ConsoleScript.tablet`/`.phone`), an `isPhone`
 *         flag selecting the resolution mode, and an injected RubricViewModel.
 * Outputs: reveal(exhibitId:) + moveToDebrief() forwarded to RubricViewModel;
 *          score(itemId:points:) on each cell tap.
 * Run: instantiated by InterviewerConsoleView (T2/T3); tests seed clocks directly.
 */

import Foundation
import Observation

@Observable
@MainActor
final class ConsoleViewModel {

    /// The active stage script — phone (6) or tablet (7), chosen by the caller.
    let stages: [ConsoleStage]

    /// Selects the stage→dim resolution mode: phone = 1:1 single dim; tablet =
    /// per-stage union of dimKeys + catch-all of unclaimed items onto the last
    /// stage (A4).
    let isPhone: Bool

    /// The shared plumbing — scoring, exhibits, reveal, and the debrief
    /// transition all go through here (A2). Injected so the same instance is
    /// shared with SessionView/DebriefView.
    let rubric: RubricViewModel

    // MARK: Stage navigation

    private(set) var stageIndex = 0

    var currentStage: ConsoleStage { stages[stageIndex] }
    var isLastStage: Bool { stageIndex == stages.count - 1 }

    func nextStage() { stageIndex = min(stages.count - 1, stageIndex + 1) }
    func prevStage() { stageIndex = max(0, stageIndex - 1) }
    func pickStage(_ index: Int) { stageIndex = min(max(0, index), stages.count - 1) }

    // MARK: Master clock (view-local, A6)

    var isMasterRunning = false
    /// Seconds elapsed on the interview clock. Settable so shot fixtures / tests
    /// can seed a representative running value (rv #8).
    var elapsedSeconds = 0

    var mmss: String { ConsoleScript.mmss(elapsedSeconds) }

    /// Seconds left against the 45-min cap; negative once over.
    private var remainingSeconds: Int { ConsoleScript.cap - elapsedSeconds }

    /// "MM:SS LEFT" while under cap, "OVER CAP" once elapsed reaches the cap.
    var nLeft: String {
        remainingSeconds > 0 ? ConsoleScript.mmss(remainingSeconds) + " LEFT" : "OVER CAP"
    }

    /// Cap-progress bar fill, 0…1.
    var capFraction: Double {
        min(1.0, Double(elapsedSeconds) / Double(ConsoleScript.cap))
    }

    /// Under-five-minutes highlight (canvas `remain < 300` — also true past the
    /// cap, which reads as continued urgency; `nLeft` shows "OVER CAP" there).
    var isUnderFiveMin: Bool { remainingSeconds < 300 }

    func toggleMaster() { isMasterRunning.toggle() }

    // MARK: Segment timer (view-local, A6)

    var isSegmentRunning = false
    var segmentElapsed = 0
    private(set) var laps: [SegmentLap] = []

    struct SegmentLap: Equatable {
        let label: String   // "Segment 0N"
        let seconds: Int
    }

    var segmentMmss: String { ConsoleScript.mmss(segmentElapsed) }

    func toggleSegment() { isSegmentRunning.toggle() }

    /// Stop the segment clock; a non-zero elapsed is appended as a "Segment 0N"
    /// lap and the clock resets. A zero-elapsed stop just halts — no lap (canvas
    /// `sgStop`).
    func stopAndLogSegment() {
        isSegmentRunning = false
        guard segmentElapsed > 0 else { return }
        let label = String(format: "Segment %02d", laps.count + 1)
        laps.append(SegmentLap(label: label, seconds: segmentElapsed))
        segmentElapsed = 0
    }

    /// Advances whichever clocks are running by one second. The view calls this
    /// from a 1 Hz timer (T2/T3); tests call it directly to advance time.
    func tick() {
        if isMasterRunning { elapsedSeconds += 1 }
        if isSegmentRunning { segmentElapsed += 1 }
    }

    // MARK: Exhibit release (SENT · mm:ss)

    /// scriptId → master-clock MM:SS captured at release (A6). Recall clears the
    /// entry (local un-mark only — reveal is one-way, A5).
    private(set) var releasedAt: [String: String] = [:]

    /// All script exhibit refs across every stage, keyed by scriptId (deduped).
    private var exhibitRefsByScriptId: [String: ConsoleExhibitRef] {
        var map: [String: ConsoleExhibitRef] = [:]
        for stage in stages {
            for ref in stage.exhibitRefs where map[ref.scriptId] == nil {
                map[ref.scriptId] = ref
            }
        }
        return map
    }

    /// The SENT · mm:ss marker for a script exhibit, if released.
    func sentAt(scriptId: String) -> String? { releasedAt[scriptId] }

    /// Captures the master-clock timestamp locally, then broadcasts the reveal
    /// through the shared plumbing (script e1/e2/e3 → ExhibitMeta.idx →
    /// .exhibitId). A missing meta still records the local marker (the shot /
    /// script row updates) but sends nothing.
    func release(scriptId: String) async {
        releasedAt[scriptId] = mmss
        guard let ref = exhibitRefsByScriptId[scriptId],
              let meta = rubric.exhibits.first(where: { $0.idx == ref.idx }) else { return }
        await rubric.reveal(exhibitId: meta.exhibitId)
    }

    /// Clears the local SENT marker + restores the Release affordance. Does NOT
    /// un-broadcast — there is no recall endpoint (A5).
    func recall(scriptId: String) { releasedAt[scriptId] = nil }

    // MARK: PDF pager

    var isPDFOpen = false
    private(set) var pdfPage = 0

    var pdfPages: [ConsolePDFPage] { ConsoleScript.pdfPages }
    var pdfPageText: String { ConsoleScript.pdfPageText(pdfPage) }

    func openPDF() { isPDFOpen = true }
    func closePDF() { isPDFOpen = false }
    func pdfNext() { pdfPage = min(ConsoleScript.pdfPages.count - 1, pdfPage + 1) }
    func pdfPrev() { pdfPage = max(0, pdfPage - 1) }

    // MARK: Scoring (toggle-clear, A2/A3)

    /// The current local point value for a dim (absent → 0).
    func points(dimId: String) -> Int { rubric.items[dimId]?.points ?? 0 }

    /// Sets the score, or clears to 0 when the same value is tapped again
    /// (backend treats absent == 0; the rail avg excludes 0 → equivalent to
    /// "unscored", no remove API — A2). Forwarded to the shared RubricViewModel.
    func score(dimId: String, points: Int) {
        let next = self.points(dimId: dimId) == points ? 0 : points
        rubric.score(itemId: dimId, points: next)
    }

    // MARK: Stage → template-item resolution (A4)

    /// Whether a stage's dimKeys claim a template item (id OR dimension match).
    private func claims(_ stage: ConsoleStage, _ item: RubricTemplateItem) -> Bool {
        stage.dimKeys.contains(item.id) || stage.dimKeys.contains(item.dimension)
    }

    /// The template items scored on the CURRENT stage.
    /// - Phone: the stage's single mapped dim (empty if the stage carries none).
    /// - Tablet: the items this stage is the FIRST to claim, plus — on the last
    ///   stage — every item no stage claims (catch-all), so no dim is dropped and
    ///   none is duplicated across stages.
    func stageItems(_ templateItems: [RubricTemplateItem]) -> [RubricTemplateItem] {
        let stage = stages[stageIndex]
        if isPhone {
            return templateItems.filter { claims(stage, $0) }
        }
        let lastIndex = stages.count - 1
        return templateItems.filter { item in
            if claims(stage, item) {
                // Assign to the first claiming stage → no duplicates.
                return stages.firstIndex(where: { claims($0, item) }) == stageIndex
            }
            // Catch-all: unclaimed items fall to the last stage.
            return stageIndex == lastIndex && !stages.contains(where: { claims($0, item) })
        }
    }

    // MARK: Running average (LOCAL, rv #4 — NOT gradePreview)

    /// Arithmetic mean of the scored dims among `items` (points > 0 only;
    /// unscored/0 excluded). Nil when nothing is scored.
    func runningAvg(_ items: [RubricTemplateItem]) -> Double? {
        let scored = items.compactMap { item -> Int? in
            let p = points(dimId: item.id)
            return p > 0 ? p : nil
        }
        guard !scored.isEmpty else { return nil }
        return Double(scored.reduce(0, +)) / Double(scored.count)
    }

    /// "NO SCORES YET" / "{avg} AVG" (canvas `scAvg`, one decimal).
    func avgText(_ items: [RubricTemplateItem]) -> String {
        guard let avg = runningAvg(items) else { return "NO SCORES YET" }
        return String(format: "%.1f AVG", avg)
    }

    // MARK: Finalize — the single close path (A2)

    /// Moves the shared session to debrief (the interviewer's real finalize
    /// control lives in DebriefView; this is the review-step trigger). No
    /// duplicate /finalize from the console.
    func finalizeAndSend() async {
        await rubric.moveToDebrief()
    }

    // MARK: Init

    init(stages: [ConsoleStage], isPhone: Bool, rubric: RubricViewModel) {
        self.stages = stages
        self.isPhone = isPhone
        self.rubric = rubric
    }
}
