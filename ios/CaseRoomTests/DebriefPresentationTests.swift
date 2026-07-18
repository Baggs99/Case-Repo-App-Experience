/*
 * Purpose: Unit tests for the F5-T5 debrief — the pure presentation rules
 *          (rubric bars from items points/max, rating-required gating, role-
 *          gated swap, the avg readout) and the DebriefViewModel behaviour
 *          (feedbackReport release detection, the 1–5 rating that clears the
 *          gate via recapClose, and the interviewer-only swap → "invite sent")
 *          over a stubbed SessionFlowService (no network).
 * Inputs: none (in-memory stub flow service + hand-built report values).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

/// Records recapClose / swap calls and returns configurable results.
final class DebriefStubFlowService: SessionFlowService {
    var feedbackResult: Result<FeedbackReport, Error>
    var recapCloseResult: Result<RecapCloseResult, Error> = .success(RecapCloseResult(closed: true, gateCleared: true))
    var swapResult: Result<SwapInitiated, Error> = .success(SwapInitiated(swapInviteId: 1, inviteeId: 16))

    private(set) var recordedRatings: [Int] = []
    private(set) var recordedThumbs: [Bool?] = []
    private(set) var swapCallCount = 0

    struct Unused: Error {}

    init(feedback: Result<FeedbackReport, Error> = .failure(Unused())) {
        self.feedbackResult = feedback
    }

    func feedbackReport(id: Int) async throws -> FeedbackReport { try feedbackResult.get() }
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult {
        recordedRatings.append(caseRating)
        recordedThumbs.append(thumbs)
        return try recapCloseResult.get()
    }
    func swap(id: Int) async throws -> SwapInitiated {
        swapCallCount += 1
        return try swapResult.get()
    }
    // Unused by DebriefViewModel.
    func negotiation(id: Int) async throws -> NegotiationView { fatalError("not used") }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { fatalError("not used") }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { fatalError("not used") }
    func swapAccept(id: Int) async throws -> SwapAccepted { fatalError("not used") }
    func recaps() async throws -> [RecapListItem] { fatalError("not used") }
    func recapViewed(id: Int) async throws -> RecapViewedResult { fatalError("not used") }
}

final class DebriefPresentationTests: XCTestCase {

    private func item(_ label: String, _ points: Int, _ max: Int = 10) -> FeedbackItem {
        FeedbackItem(id: label, label: label, dimension: label, maxPoints: max, points: points, note: "")
    }

    private func report(grade: Double? = 7.2, finalizedAt: String? = "2026-07-16T21:00:00Z") -> FeedbackReport {
        FeedbackReport(
            grade: grade, finalizedAt: finalizedAt, notesMd: "Get there sooner.",
            items: [item("Structure", 8), item("Quant", 6), item("Communication", 8), item("Synthesis", 7)],
            reveals: [], caseId: 91, caseTitle: "Nordic carrier")
    }

    // MARK: - Bars from items points/max

    func testBarFractionFromPointsAndMax() {
        XCTAssertEqual(DebriefPresentation.barFraction(points: 8, max: 10), 0.8, accuracy: 0.0001)
        XCTAssertEqual(DebriefPresentation.barFraction(points: 6, max: 10), 0.6, accuracy: 0.0001)
        XCTAssertEqual(DebriefPresentation.barFraction(points: 7, max: 10), 0.7, accuracy: 0.0001)
    }

    func testBarFractionClampsAndGuardsZeroMax() {
        XCTAssertEqual(DebriefPresentation.barFraction(points: 12, max: 10), 1.0)  // clamps high
        XCTAssertEqual(DebriefPresentation.barFraction(points: -3, max: 10), 0.0)  // clamps low
        XCTAssertEqual(DebriefPresentation.barFraction(points: 5, max: 0), 0.0)    // no divide-by-zero
    }

    // MARK: - Rating-required gating

    func testRatingValidityIsOneThroughFive() {
        XCTAssertFalse(DebriefPresentation.isValidRating(0))
        XCTAssertTrue(DebriefPresentation.isValidRating(1))
        XCTAssertTrue(DebriefPresentation.isValidRating(5))
        XCTAssertFalse(DebriefPresentation.isValidRating(6))
        XCTAssertFalse(DebriefPresentation.isValidRating(-1))
    }

    // MARK: - Role-gated swap

    func testSwapAvailableOnlyForInterviewer() {
        XCTAssertTrue(DebriefPresentation.swapAvailable(role: "interviewer"))
        XCTAssertFalse(DebriefPresentation.swapAvailable(role: "candidate"))
        XCTAssertFalse(DebriefPresentation.swapAvailable(role: nil))
    }

    // MARK: - Avg readout + release detection

    func testAvgTextFormatsOrDashes() {
        XCTAssertEqual(DebriefPresentation.avgText(7.2), "7.2")
        XCTAssertEqual(DebriefPresentation.avgText(nil), "—")
        XCTAssertEqual(DebriefPresentation.dimensionsLabel(count: 4), "AVG OF 4 DIMENSIONS")
    }

    func testIsReleasedRequiresGradeOrFinalizedAt() {
        XCTAssertFalse(DebriefPresentation.isReleased(nil))
        XCTAssertTrue(DebriefPresentation.isReleased(report()))
        XCTAssertFalse(DebriefPresentation.isReleased(report(grade: nil, finalizedAt: nil)))
        XCTAssertTrue(DebriefPresentation.isReleased(report(grade: nil, finalizedAt: "2026-07-16T21:00:00Z")))
    }

    // MARK: - View model: release detection

    @MainActor
    func testLoadReportMarksReleasedWhenFinalized() async {
        let vm = DebriefViewModel(sessionId: 4040, flow: DebriefStubFlowService(feedback: .success(report())))
        XCTAssertFalse(vm.released)
        await vm.loadReport()
        XCTAssertTrue(vm.loaded)
        XCTAssertTrue(vm.released)
        XCTAssertEqual(vm.report?.items.count, 4)
    }

    @MainActor
    func testLoadReportStaysWaitingOn409() async {
        let vm = DebriefViewModel(sessionId: 4040, flow: DebriefStubFlowService(feedback: .failure(DebriefStubFlowService.Unused())))
        await vm.loadReport()
        XCTAssertTrue(vm.loaded)       // load attempt completed…
        XCTAssertFalse(vm.released)    // …but nothing to release yet
        XCTAssertNil(vm.report)
    }

    // MARK: - View model: rating clears the gate

    @MainActor
    func testValidRatingClosesRecapAndClearsGate() async {
        let flow = DebriefStubFlowService()
        flow.recapCloseResult = .success(RecapCloseResult(closed: true, gateCleared: true))
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.rate(4)

        XCTAssertEqual(flow.recordedRatings, [4])
        XCTAssertEqual(flow.recordedThumbs.count, 1)
        XCTAssertNil(flow.recordedThumbs.first!)            // candidate has no thumbs
        XCTAssertEqual(vm.rating, 4)
        XCTAssertTrue(vm.gateCleared)
        XCTAssertNil(vm.rateError)
    }

    @MainActor
    func testInvalidRatingDoesNotCloseRecap() async {
        let flow = DebriefStubFlowService()
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.rate(0)     // out of 1…5 — must not call recapClose

        XCTAssertTrue(flow.recordedRatings.isEmpty)
        XCTAssertEqual(vm.rating, 0)
        XCTAssertFalse(vm.gateCleared)
    }

    @MainActor
    func testRatingTreats409AsCleared() async {
        // An already-closed recap 409s. Parity with RecapCloseOutViewModel: the
        // gate is already clear — keep the rating, clear the gate, no false error.
        let flow = DebriefStubFlowService()
        flow.recapCloseResult = .failure(APIError.server(409))
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.rate(4)

        XCTAssertEqual(flow.recordedRatings, [4])   // attempted…
        XCTAssertEqual(vm.rating, 4)                 // …rating kept (no rollback)
        XCTAssertTrue(vm.gateCleared)
        XCTAssertNil(vm.rateError)
    }

    @MainActor
    func testRateNoOpAfterGateCleared() async {
        // In-flight/cleared guard (mirrors RecapCloseOutViewModel): once the gate
        // is cleared, a further tap must not fire a second recapClose.
        let flow = DebriefStubFlowService()
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.rate(4)
        XCTAssertTrue(vm.gateCleared)

        await vm.rate(2)                             // already cleared → ignored
        XCTAssertEqual(flow.recordedRatings, [4])    // only the first close fired
        XCTAssertEqual(vm.rating, 4)                 // unchanged
    }

    @MainActor
    func testRatingRollsBackOnCloseFailure() async {
        let flow = DebriefStubFlowService()
        flow.recapCloseResult = .failure(DebriefStubFlowService.Unused())
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.rate(3)

        XCTAssertEqual(flow.recordedRatings, [3])   // attempted…
        XCTAssertEqual(vm.rating, 0)                 // …but rolled back (no false confirmed cells)
        XCTAssertFalse(vm.gateCleared)
        XCTAssertNotNil(vm.rateError)
    }

    // MARK: - View model: interviewer-only swap → invite sent

    @MainActor
    func testSwapSendsInviteOnSuccess() async {
        let flow = DebriefStubFlowService()
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.initiateSwap()

        XCTAssertEqual(flow.swapCallCount, 1)
        XCTAssertTrue(vm.swapSent)
        XCTAssertNil(vm.swapError)
    }

    @MainActor
    func testSwapSurfacesErrorOnFailure() async {
        let flow = DebriefStubFlowService()
        flow.swapResult = .failure(DebriefStubFlowService.Unused())
        let vm = DebriefViewModel(sessionId: 4040, flow: flow)

        await vm.initiateSwap()

        XCTAssertFalse(vm.swapSent)
        XCTAssertNotNil(vm.swapError)
    }
}
