/*
 * Purpose: Unit tests for the recap REPORT page's presentation model (F5 Task 6)
 *          — proves the released feedback report maps to rubric bars + serif
 *          paragraphs, the interviewer attribution enriches from the recap list,
 *          recapViewed fires on appear (and a 409/403 is swallowed), and the pure
 *          RecapPresentation rules (bar fill, paragraph split, item notes,
 *          attribution/subline/date) behave.
 * Inputs: none — drives RecapViewModel with an in-test stub SessionFlowService.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom test
 */

import XCTest
@testable import CaseRoom

// A recording stub SessionFlowService: serves a canned report + recap list,
// records the recapViewed calls, and can be told to throw on recapViewed (the
// interviewer 403 / re-view 409 the VM must swallow). Only the three recap-report
// methods are exercised; the rest are unreachable and fatalError if hit.
private final class StubRecapFlow: SessionFlowService, @unchecked Sendable {
    var report: FeedbackReport?
    var recapList: [RecapListItem]
    var viewedThrows = false
    private(set) var viewedCalls: [Int] = []

    init(report: FeedbackReport?, recaps: [RecapListItem] = [], viewedThrows: Bool = false) {
        self.report = report
        self.recapList = recaps
        self.viewedThrows = viewedThrows
    }

    enum StubError: Error { case blocked, unused }

    func feedbackReport(id: Int) async throws -> FeedbackReport {
        guard let report else { throw StubError.unused }
        return report
    }
    func recaps() async throws -> [RecapListItem] { recapList }
    func recapViewed(id: Int) async throws -> RecapViewedResult {
        viewedCalls.append(id)
        if viewedThrows { throw StubError.blocked }
        return RecapViewedResult(viewed: true)
    }

    func negotiation(id: Int) async throws -> NegotiationView { fatalError("unused") }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { fatalError("unused") }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { fatalError("unused") }
    func swap(id: Int) async throws -> SwapInitiated { fatalError("unused") }
    func swapAccept(id: Int) async throws -> SwapAccepted { fatalError("unused") }
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult { fatalError("unused") }
}

// A report with three notes_md paragraphs and 4 rubric items (7/5/8/6 out of 10).
private func makeReport(sessionCaseId: Int = 55) -> FeedbackReport {
    FeedbackReport(
        grade: 4.1,
        finalizedAt: "2026-07-12T16:34:00Z",
        notesMd: "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.",
        items: [
            FeedbackItem(id: "structure", label: "Structure", dimension: "structure", maxPoints: 10, points: 7, note: ""),
            FeedbackItem(id: "quant", label: "Quant", dimension: "quant", maxPoints: 10, points: 5, note: "Units slip"),
            FeedbackItem(id: "comm", label: "Communication", dimension: "comm", maxPoints: 10, points: 8, note: ""),
            FeedbackItem(id: "synth", label: "Synthesis", dimension: "synth", maxPoints: 10, points: 6, note: ""),
        ],
        reveals: [],
        caseId: sessionCaseId,
        caseTitle: "Ski resort: revenue up, profit down")
}

private func makeRecapItem(sessionId: Int) -> RecapListItem {
    RecapListItem(
        sessionId: sessionId, caseId: 55, caseTitle: "Ski resort: revenue up, profit down",
        interviewerName: "T. Becker", grade: 4.1,
        finalizedAt: "2026-07-12T16:34:00Z", viewedAt: nil)
}

@MainActor
final class RecapViewModelTests: XCTestCase {

    // MARK: - Fetch → bars / paragraphs mapping

    func testLoadReportMapsBarsAndParagraphs() async {
        let flow = StubRecapFlow(report: makeReport())
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.loadReport()

        XCTAssertTrue(vm.loaded)
        XCTAssertEqual(vm.items.count, 4)                       // rubric bars
        XCTAssertEqual(vm.items.map(\.points), [7, 5, 8, 6])
        XCTAssertEqual(vm.paragraphs, ["First paragraph.", "Second paragraph.", "Third paragraph."])
        XCTAssertEqual(vm.caseTitle, "Ski resort: revenue up, profit down")
    }

    func testItemNotesKeepsOnlyScoredNotes() async {
        let flow = StubRecapFlow(report: makeReport())
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.loadReport()

        // Only Quant carries a note in the fixture.
        XCTAssertEqual(vm.itemNotes.count, 1)
        XCTAssertEqual(vm.itemNotes.first?.label, "Quant")
        XCTAssertEqual(vm.itemNotes.first?.note, "Units slip")
    }

    // MARK: - Interviewer attribution enriches from recaps()

    func testLoadEnrichesInterviewerFromRecapList() async {
        let flow = StubRecapFlow(report: makeReport(), recaps: [makeRecapItem(sessionId: 5150)])
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.loadReport()

        XCTAssertEqual(vm.interviewerName, "T. Becker")
        XCTAssertEqual(vm.subline, "Feedback from T. Becker · rated 4.1 / 5")
        XCTAssertEqual(vm.dateKicker, "JUL 12, 2026")
    }

    func testAttributionFallsBackWhenNoMatchingRecap() async {
        // recaps() returns a row for a DIFFERENT session → no enrichment.
        let flow = StubRecapFlow(report: makeReport(), recaps: [makeRecapItem(sessionId: 9999)])
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.loadReport()

        XCTAssertNil(vm.interviewerName)
        // Name falls back, but the grade still comes from the report itself
        // (recapItem?.grade ?? report?.grade), so the rating is never dropped.
        XCTAssertEqual(vm.subline, "Feedback from Your interviewer · rated 4.1 / 5")
    }

    // MARK: - recapViewed on appear (candidate-only; swallow 409/403)

    func testOnAppearMarksViewed() async {
        let flow = StubRecapFlow(report: makeReport(), recaps: [makeRecapItem(sessionId: 5150)])
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.onAppear()

        XCTAssertEqual(flow.viewedCalls, [5150])
        XCTAssertTrue(vm.viewedMarked)
        XCTAssertNotNil(vm.report)          // report still rendered
    }

    func testOnAppearSwallowsViewedFailure() async {
        let flow = StubRecapFlow(report: makeReport(), viewedThrows: true)
        let vm = RecapViewModel(sessionId: 5150, flow: flow)

        await vm.onAppear()

        XCTAssertEqual(flow.viewedCalls, [5150])  // it was attempted
        XCTAssertFalse(vm.viewedMarked)           // …and the 409/403 was swallowed
        XCTAssertNotNil(vm.report)                // report unaffected
    }

    // MARK: - Pure RecapPresentation rules

    func testBarFractionClamps() {
        XCTAssertEqual(RecapPresentation.barFraction(points: 7, max: 10), 0.7, accuracy: 0.0001)
        XCTAssertEqual(RecapPresentation.barFraction(points: 12, max: 10), 1.0)   // over-max clamps to full
        XCTAssertEqual(RecapPresentation.barFraction(points: -3, max: 10), 0.0)   // negative clamps to empty
        XCTAssertEqual(RecapPresentation.barFraction(points: 5, max: 0), 0.0)     // zero max → empty, no divide-by-zero
    }

    func testParagraphsSplitTrimAndDropEmpties() {
        XCTAssertEqual(RecapPresentation.paragraphs("A\n\nB"), ["A", "B"])
        XCTAssertEqual(RecapPresentation.paragraphs("  A  \n\n\n  B  "), ["A", "B"])  // extra blanks + whitespace
        XCTAssertEqual(RecapPresentation.paragraphs("Single line, soft\nwrap"), ["Single line, soft\nwrap"])
        XCTAssertEqual(RecapPresentation.paragraphs("   "), [])
    }

    func testAttributionFallback() {
        XCTAssertEqual(RecapPresentation.attribution("T. Becker"), "T. Becker")
        XCTAssertEqual(RecapPresentation.attribution(nil), "Your interviewer")
        XCTAssertEqual(RecapPresentation.attribution("  "), "Your interviewer")
    }

    func testFeedbackHeadingUppercases() {
        XCTAssertEqual(RecapPresentation.feedbackHeading("T. Becker"), "WHAT T. BECKER WROTE")
        XCTAssertEqual(RecapPresentation.feedbackHeading(nil), "WHAT YOUR INTERVIEWER WROTE")
    }

    func testSublineWithAndWithoutGrade() {
        XCTAssertEqual(RecapPresentation.subline(name: "T. Becker", grade: 4.1), "Feedback from T. Becker · rated 4.1 / 5")
        XCTAssertEqual(RecapPresentation.subline(name: "T. Becker", grade: nil), "Feedback from T. Becker")
    }
}
