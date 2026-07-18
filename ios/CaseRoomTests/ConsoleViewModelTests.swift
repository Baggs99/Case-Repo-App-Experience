/*
 * Purpose: Unit tests for the F6 interviewer console foundation —
 *          ConsoleViewModel (clocks, stage nav, dim resolution, exhibit
 *          release/recall, toggle-clear scoring, running-avg, finalize path)
 *          + the authored ConsoleScript model. A recording stub SessionService
 *          (mirrors F5's SessionFixtures stubs) captures the transition target
 *          so finalizeAndSend → moveToDebrief is asserted without a server.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

/// Records the plumbing calls the console forwards (reveal exhibit ids, the
/// transition target). Serves a supplied rubric + exhibits; unused endpoints
/// fatal-error (never hit on the console path).
final class ConsoleStubSessionService: SessionService {
    let rubricState: RubricState
    let exhibitList: [ExhibitMeta]

    private(set) var recordedTransitionTargets: [String] = []
    private(set) var recordedRevealExhibitIds: [Int] = []

    init(rubric: RubricState, exhibits: [ExhibitMeta] = []) {
        self.rubricState = rubric
        self.exhibitList = exhibits
    }

    func rubric(id: Int) async throws -> RubricState { rubricState }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double {
        rubricState.gradePreview
    }
    func exhibits(id: Int) async throws -> [ExhibitMeta] { exhibitList }
    func reveal(id: Int, exhibitId: Int) async throws { recordedRevealExhibitIds.append(exhibitId) }
    func transition(id: Int, target: String) async throws -> SessionDetail {
        recordedTransitionTargets.append(target)
        return Self.stubDetail
    }

    // Unused by the console path.
    func sessionDetail(id: Int) async throws -> SessionDetail { Self.stubDetail }
    func joinConfig(id: Int) async throws -> JoinConfig { fatalError("not used") }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { Self.stubDetail }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { fatalError("not used") }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { fatalError("not used") }
    func completeRecording(id: Int) async throws { fatalError("not used") }
    func finalize(id: Int, grade: Double?) async throws -> Finalized { fatalError("not used") }

    static let stubDetail = SessionDetail(
        id: 1, interviewerId: 1, candidateId: 2, caseId: 7, state: "debrief", mode: "remote",
        consentInterviewer: true, consentCandidate: true,
        scheduledAt: nil, startedAt: nil, endedAt: nil,
        interviewerName: nil, candidateName: nil, caseTitle: nil, yourRole: "interviewer")
}

@MainActor
final class ConsoleViewModelTests: XCTestCase {

    // MARK: Fixtures

    /// The real shipping template (webapp/repositories/practice_sessions.py):
    /// 5 dims / max 5, id == dimension.
    private func realTemplate() -> [RubricTemplateItem] {
        [
            RubricTemplateItem(id: "structure", label: "Structuring & framework", dimension: "structure", maxPoints: 5),
            RubricTemplateItem(id: "quant", label: "Quantitative accuracy", dimension: "quant", maxPoints: 5),
            RubricTemplateItem(id: "insight", label: "Business insight", dimension: "insight", maxPoints: 5),
            RubricTemplateItem(id: "communication", label: "Communication & presence", dimension: "communication", maxPoints: 5),
            RubricTemplateItem(id: "synthesis", label: "Synthesis & recommendation", dimension: "synthesis", maxPoints: 5),
        ]
    }

    /// The canvas 12-dim / max-10 template (DIMS keys) — every key matches a
    /// tablet stage's dimKeys, so none should fall to the catch-all.
    private func canvasTemplate() -> [RubricTemplateItem] {
        ["fit", "star", "summary", "comm", "questions", "structure",
         "quant", "judgment", "creativity", "synthesis", "leading", "time"]
            .map { RubricTemplateItem(id: $0, label: $0.capitalized, dimension: $0, maxPoints: 10) }
    }

    private func makeRubric(template: [RubricTemplateItem],
                            items: [String: RubricItemScore] = [:],
                            exhibits: [ExhibitMeta] = [],
                            service: ConsoleStubSessionService? = nil) -> (RubricViewModel, ConsoleStubSessionService) {
        let state = RubricState(templateItems: template, items: items, notesMd: "",
                                gradePreview: 0, grade: nil, finalizedAt: nil)
        let svc = service ?? ConsoleStubSessionService(rubric: state, exhibits: exhibits)
        let vm = RubricViewModel(sessionId: 1, service: svc)
        vm.templateItems = template
        vm.items = items
        vm.exhibits = exhibits
        return (vm, svc)
    }

    private func tabletVM(template: [RubricTemplateItem],
                          items: [String: RubricItemScore] = [:],
                          exhibits: [ExhibitMeta] = []) -> (ConsoleViewModel, ConsoleStubSessionService) {
        let (rvm, svc) = makeRubric(template: template, items: items, exhibits: exhibits)
        return (ConsoleViewModel(stages: ConsoleScript.tablet, isPhone: false, rubric: rvm), svc)
    }

    private func phoneVM(template: [RubricTemplateItem],
                         items: [String: RubricItemScore] = [:]) -> (ConsoleViewModel, ConsoleStubSessionService) {
        let (rvm, svc) = makeRubric(template: template, items: items)
        return (ConsoleViewModel(stages: ConsoleScript.phone, isPhone: true, rubric: rvm), svc)
    }

    // MARK: Script shape

    func testStageCounts() {
        XCTAssertEqual(ConsoleScript.tablet.count, 7)
        XCTAssertEqual(ConsoleScript.phone.count, 6)
        XCTAssertEqual(ConsoleScript.tablet.first?.name, "BEHAVIORAL")
        XCTAssertEqual(ConsoleScript.phone.first?.name, "OPENING")   // BEHAVIORAL dropped
        XCTAssertEqual(ConsoleScript.tablet.last?.name, "CLOSE")
        XCTAssertEqual(ConsoleScript.cap, 45 * 60)
    }

    func testExhibitRefsMapToIdx() {
        // e1/e2 on QUANT (idx 0/1), e3 on BRAINSTORM (idx 2).
        let quant = ConsoleScript.tablet[4]
        XCTAssertEqual(quant.name, "QUANT")
        XCTAssertEqual(quant.exhibitRefs.map(\.scriptId), ["e1", "e2"])
        XCTAssertEqual(quant.exhibitRefs.map(\.idx), [0, 1])
        let brainstorm = ConsoleScript.tablet[5]
        XCTAssertEqual(brainstorm.exhibitRefs.map(\.scriptId), ["e3"])
        XCTAssertEqual(brainstorm.exhibitRefs.map(\.idx), [2])
    }

    // MARK: Stage navigation bounds

    func testTabletStageNavBounds() {
        let (vm, _) = tabletVM(template: realTemplate())
        XCTAssertEqual(vm.stageIndex, 0)
        vm.prevStage()
        XCTAssertEqual(vm.stageIndex, 0)                // clamped at 0
        for _ in 0..<20 { vm.nextStage() }
        XCTAssertEqual(vm.stageIndex, 6)                // clamped at count-1 (7 stages)
        XCTAssertTrue(vm.isLastStage)
        vm.pickStage(99)
        XCTAssertEqual(vm.stageIndex, 6)
        vm.pickStage(-5)
        XCTAssertEqual(vm.stageIndex, 0)
        vm.pickStage(3)
        XCTAssertEqual(vm.stageIndex, 3)
    }

    func testPhoneStageNavBounds() {
        let (vm, _) = phoneVM(template: realTemplate())
        for _ in 0..<20 { vm.nextStage() }
        XCTAssertEqual(vm.stageIndex, 5)                // 6 stages
        XCTAssertTrue(vm.isLastStage)
    }

    // MARK: Dim resolution — tablet union + catch-all coverage

    func testTabletResolutionRealTemplateCoverage() {
        let (vm, _) = tabletVM(template: realTemplate())
        assertFullCoverageNoDrops(vm, template: realTemplate())
        // Spot the 1:1 real placements.
        vm.pickStage(3); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["structure"])   // FRAMEWORK
        vm.pickStage(4)                                                                            // QUANT
        XCTAssertEqual(Set(vm.stageItems(realTemplate()).map(\.id)), ["quant", "insight"])
        vm.pickStage(6); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["synthesis"])    // CLOSE
        vm.pickStage(1); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["communication"])// OPENING
    }

    func testTabletResolutionCanvasTemplateNoCatchAllLeak() {
        let (vm, _) = tabletVM(template: canvasTemplate())
        assertFullCoverageNoDrops(vm, template: canvasTemplate())
        // Every canvas key is explicitly claimed → CLOSE holds only its own dims,
        // NOT a catch-all pile.
        vm.pickStage(6)
        XCTAssertEqual(Set(vm.stageItems(canvasTemplate()).map(\.id)), ["synthesis", "leading", "time"])
    }

    func testTabletCatchAllCapturesUnclaimedDims() {
        // A synthetic 12-dim / max-10 template whose dims match NO stage — every
        // item must land on the last stage (catch-all), none dropped.
        let synthetic = (1...12).map {
            RubricTemplateItem(id: "x\($0)", label: "X\($0)", dimension: "x\($0)", maxPoints: 10)
        }
        let (vm, _) = tabletVM(template: synthetic)
        assertFullCoverageNoDrops(vm, template: synthetic)
        // Non-last stages surface nothing; CLOSE surfaces all 12.
        vm.pickStage(0); XCTAssertTrue(vm.stageItems(synthetic).isEmpty)
        vm.pickStage(6); XCTAssertEqual(vm.stageItems(synthetic).count, 12)
    }

    func testTabletMixedTemplatePartialCatchAll() {
        // Some claimed (structure/quant), some orphaned (foo/bar) → orphans to CLOSE.
        let mixed = [
            RubricTemplateItem(id: "structure", label: "S", dimension: "structure", maxPoints: 10),
            RubricTemplateItem(id: "quant", label: "Q", dimension: "quant", maxPoints: 10),
            RubricTemplateItem(id: "foo", label: "F", dimension: "foo", maxPoints: 10),
            RubricTemplateItem(id: "bar", label: "B", dimension: "bar", maxPoints: 10),
        ]
        let (vm, _) = tabletVM(template: mixed)
        assertFullCoverageNoDrops(vm, template: mixed)
        vm.pickStage(3); XCTAssertEqual(vm.stageItems(mixed).map(\.id), ["structure"])
        vm.pickStage(4); XCTAssertEqual(vm.stageItems(mixed).map(\.id), ["quant"])
        vm.pickStage(6)  // CLOSE claims none of these + catch-all orphans foo/bar
        XCTAssertEqual(Set(vm.stageItems(mixed).map(\.id)), ["foo", "bar"])
    }

    // MARK: Dim resolution — phone 1:1 coverage on distinct stages

    func testPhoneResolutionRealTemplateDistinctStages() {
        let (vm, _) = phoneVM(template: realTemplate())
        assertFullCoverageNoDrops(vm, template: realTemplate())
        vm.pickStage(0); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["communication"]) // OPENING
        vm.pickStage(1); XCTAssertTrue(vm.stageItems(realTemplate()).isEmpty)                        // CLARIFY hidden
        vm.pickStage(2); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["structure"])      // FRAMEWORK
        vm.pickStage(3); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["quant"])          // QUANT
        vm.pickStage(4); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["insight"])        // BRAINSTORM
        vm.pickStage(5); XCTAssertEqual(vm.stageItems(realTemplate()).map(\.id), ["synthesis"])      // CLOSE
        // No phone stage ever shows more than one dim.
        for i in 0..<vm.stages.count {
            vm.pickStage(i)
            XCTAssertLessThanOrEqual(vm.stageItems(realTemplate()).count, 1)
        }
    }

    /// Asserts every template dim is surfaced by the RENDERED score UI across the
    /// stages exactly once (coverage guarantee + no catch-all double-count).
    private func assertFullCoverageNoDrops(_ vm: ConsoleViewModel, template: [RubricTemplateItem],
                                           file: StaticString = #file, line: UInt = #line) {
        var seen: [String] = []
        for i in 0..<vm.stages.count {
            vm.pickStage(i)
            seen += vm.stageItems(template).map(\.id)
        }
        XCTAssertEqual(Set(seen), Set(template.map(\.id)), "every dim surfaced", file: file, line: line)
        XCTAssertEqual(seen.count, template.count, "no dim dropped or duplicated", file: file, line: line)
        vm.pickStage(0)
    }

    // MARK: Master clock math

    func testMasterClockAndCap() {
        let (vm, _) = tabletVM(template: realTemplate())
        XCTAssertEqual(vm.mmss, "00:00")
        XCTAssertEqual(vm.nLeft, "45:00 LEFT")
        XCTAssertEqual(vm.capFraction, 0, accuracy: 0.0001)
        XCTAssertFalse(vm.isUnderFiveMin)

        vm.elapsedSeconds = 754                          // 12:34
        XCTAssertEqual(vm.mmss, "12:34")
        XCTAssertEqual(vm.nLeft, ConsoleScript.mmss(45 * 60 - 754) + " LEFT")  // 32:26 LEFT
        XCTAssertEqual(vm.capFraction, 754.0 / 2700.0, accuracy: 0.0001)
        XCTAssertFalse(vm.isUnderFiveMin)

        vm.elapsedSeconds = 2500                         // remain 200 < 300
        XCTAssertTrue(vm.isUnderFiveMin)
        XCTAssertEqual(vm.nLeft, "03:20 LEFT")

        vm.elapsedSeconds = 2700                         // exactly cap → OVER CAP
        XCTAssertEqual(vm.nLeft, "OVER CAP")
        XCTAssertEqual(vm.capFraction, 1.0, accuracy: 0.0001)

        vm.elapsedSeconds = 3000                         // over cap: fraction clamps
        XCTAssertEqual(vm.nLeft, "OVER CAP")
        XCTAssertEqual(vm.capFraction, 1.0, accuracy: 0.0001)
    }

    func testMasterTickOnlyWhenRunning() {
        let (vm, _) = tabletVM(template: realTemplate())
        vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 0)             // not running
        vm.toggleMaster()
        vm.tick(); vm.tick(); vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 3)
        vm.toggleMaster()
        vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 3)             // paused
    }

    // MARK: Segment timer + laps

    func testSegmentLapsAndNumbering() {
        let (vm, _) = tabletVM(template: realTemplate())
        vm.toggleSegment()
        for _ in 0..<65 { vm.tick() }                    // 01:05
        XCTAssertEqual(vm.segmentMmss, "01:05")
        vm.stopAndLogSegment()
        XCTAssertEqual(vm.laps.count, 1)
        XCTAssertEqual(vm.laps[0].label, "Segment 01")
        XCTAssertEqual(vm.laps[0].seconds, 65)
        XCTAssertEqual(vm.segmentElapsed, 0)             // reset
        XCTAssertFalse(vm.isSegmentRunning)

        vm.toggleSegment()
        for _ in 0..<30 { vm.tick() }
        vm.stopAndLogSegment()
        XCTAssertEqual(vm.laps.count, 2)
        XCTAssertEqual(vm.laps[1].label, "Segment 02")
    }

    func testSegmentZeroElapsedNoLap() {
        let (vm, _) = tabletVM(template: realTemplate())
        vm.toggleSegment()                               // running, 0 elapsed
        vm.stopAndLogSegment()
        XCTAssertTrue(vm.laps.isEmpty)                   // no lap
        XCTAssertFalse(vm.isSegmentRunning)              // just stopped
    }

    // MARK: Exhibit release / recall + reveal forwarding

    func testReleaseCapturesTimestampAndForwardsReveal() async {
        let meta0 = ExhibitMeta(exhibitId: 501, idx: 0, sourcePages: "2", width: 1, height: 1, bytes: 1, ivB64: "")
        let meta1 = ExhibitMeta(exhibitId: 777, idx: 1, sourcePages: "3", width: 1, height: 1, bytes: 1, ivB64: "")
        let (vm, svc) = tabletVM(template: realTemplate(), exhibits: [meta0, meta1])
        vm.elapsedSeconds = 754                          // 12:34
        XCTAssertNil(vm.sentAt(scriptId: "e1"))

        await vm.release(scriptId: "e1")
        XCTAssertEqual(vm.sentAt(scriptId: "e1"), "12:34")
        XCTAssertEqual(svc.recordedRevealExhibitIds, [501])   // e1 → idx 0 → 501

        await vm.release(scriptId: "e2")                 // e2 → idx 1 → 777
        XCTAssertEqual(svc.recordedRevealExhibitIds, [501, 777])
    }

    func testRecallClearsLocalMarkerOnly() async {
        let meta0 = ExhibitMeta(exhibitId: 501, idx: 0, sourcePages: "2", width: 1, height: 1, bytes: 1, ivB64: "")
        let (vm, svc) = tabletVM(template: realTemplate(), exhibits: [meta0])
        vm.elapsedSeconds = 60
        await vm.release(scriptId: "e1")
        XCTAssertEqual(vm.sentAt(scriptId: "e1"), "01:00")

        vm.recall(scriptId: "e1")
        XCTAssertNil(vm.sentAt(scriptId: "e1"))          // local marker cleared
        XCTAssertEqual(svc.recordedRevealExhibitIds, [501])  // NO un-broadcast (A5)
    }

    // MARK: Scoring — toggle-clear + running avg

    func testToggleClearScore() {
        let (vm, _) = tabletVM(template: realTemplate())
        vm.score(dimId: "quant", points: 4)
        XCTAssertEqual(vm.points(dimId: "quant"), 4)
        vm.score(dimId: "quant", points: 4)              // same value → clear
        XCTAssertEqual(vm.points(dimId: "quant"), 0)
        vm.score(dimId: "quant", points: 5)
        XCTAssertEqual(vm.points(dimId: "quant"), 5)     // new value sets
    }

    func testRunningAvgExcludesZeroAndAvgText() {
        let (vm, _) = tabletVM(template: realTemplate())
        let items = realTemplate()
        XCTAssertNil(vm.runningAvg(items))
        XCTAssertEqual(vm.avgText(items), "NO SCORES YET")

        vm.score(dimId: "structure", points: 8)
        vm.score(dimId: "quant", points: 6)
        vm.score(dimId: "insight", points: 0)            // 0 excluded
        XCTAssertEqual(vm.runningAvg(items)!, 7.0, accuracy: 0.0001)
        XCTAssertEqual(vm.avgText(items), "7.0 AVG")

        vm.score(dimId: "communication", points: 7)      // {8,6,7} → 7.0
        XCTAssertEqual(vm.avgText(items), "7.0 AVG")
        vm.score(dimId: "synthesis", points: 9)          // {8,6,7,9} → 7.5
        XCTAssertEqual(vm.avgText(items), "7.5 AVG")
    }

    // MARK: PDF pager

    func testPDFPagerBounds() {
        let (vm, _) = tabletVM(template: realTemplate())
        XCTAssertFalse(vm.isPDFOpen)
        vm.openPDF(); XCTAssertTrue(vm.isPDFOpen)
        XCTAssertEqual(vm.pdfPage, 0)
        vm.pdfPrev(); XCTAssertEqual(vm.pdfPage, 0)      // clamped
        XCTAssertEqual(vm.pdfPageText, "PAGE 01 OF 08")
        vm.pdfNext(); vm.pdfNext()
        XCTAssertEqual(vm.pdfPage, 2)
        XCTAssertEqual(vm.pdfPageText, "PAGE 03 OF 08 — 04–08 IN THE FULL PACK")
        vm.pdfNext(); XCTAssertEqual(vm.pdfPage, 2)      // clamped at last
        vm.closePDF(); XCTAssertFalse(vm.isPDFOpen)
    }

    func testPDFPagesAuthored() {
        XCTAssertEqual(ConsoleScript.pdfPages.count, 3)
        XCTAssertEqual(ConsoleScript.pdfPages[0].corner, .meta("D4 · ~40 MIN"))
        XCTAssertEqual(ConsoleScript.pdfPages[1].corner, .exhibitRelease(scriptId: "e1"))
        XCTAssertEqual(ConsoleScript.pdfPages[2].corner, .interviewerOnly)
    }

    // MARK: Finalize → moveToDebrief (single close path, A2)

    func testFinalizeAndSendMovesToDebrief() async {
        let (vm, svc) = tabletVM(template: realTemplate())
        await vm.finalizeAndSend()
        XCTAssertEqual(svc.recordedTransitionTargets, ["debrief"])
    }
}
