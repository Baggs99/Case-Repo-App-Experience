/*
 * Purpose: Unit tests for the recap CLOSE-OUT sheet (F5 Task 7) — the GATE. Proves
 *          the pure rules (scroll progress, the bottom − 16 unlock threshold, the
 *          N% label, the required-rating gate) and the view model's close flow:
 *          Close is disabled without a 1–5, a valid rating clears the gate and
 *          raises the "Gate cleared." toast + dismissal, a 409 re-close is treated
 *          as already-cleared, and a defensive 422 rolls the rating back.
 * Inputs: none — drives RecapCloseOutViewModel with an in-test stub SessionFlowService.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom test
 */

import XCTest
@testable import CaseRoom

// A recording stub SessionFlowService: records recapClose calls and can be told
// to throw a chosen APIError.server(status). Only recapClose is exercised; the
// rest are unreachable and fatalError if hit.
private final class StubCloseFlow: SessionFlowService, @unchecked Sendable {
    var throwStatus: Int?
    private(set) var closeCalls: [(rating: Int, thumbs: Bool?)] = []

    init(throwStatus: Int? = nil) { self.throwStatus = throwStatus }

    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult {
        closeCalls.append((caseRating, thumbs))
        if let status = throwStatus { throw APIError.server(status) }
        return RecapCloseResult(closed: true, gateCleared: true)
    }

    func negotiation(id: Int) async throws -> NegotiationView { fatalError("unused") }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { fatalError("unused") }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { fatalError("unused") }
    func swap(id: Int) async throws -> SwapInitiated { fatalError("unused") }
    func swapAccept(id: Int) async throws -> SwapAccepted { fatalError("unused") }
    func recaps() async throws -> [RecapListItem] { fatalError("unused") }
    func recapViewed(id: Int) async throws -> RecapViewedResult { fatalError("unused") }
    func feedbackReport(id: Int) async throws -> FeedbackReport { fatalError("unused") }
}

@MainActor
final class RecapCloseOutViewModelTests: XCTestCase {

    // MARK: - Pure scroll-progress / unlock threshold (bottom − 16)

    func testScrollProgressClamps() {
        // content 1000, viewport 600 → scrollable 400.
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 200, contentHeight: 1000, viewportHeight: 600), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 0, contentHeight: 1000, viewportHeight: 600), 0)
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 400, contentHeight: 1000, viewportHeight: 600), 1)
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 999, contentHeight: 1000, viewportHeight: 600), 1)  // over-scroll clamps
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 0, contentHeight: 0, viewportHeight: 0), 0)         // unmeasured
        XCTAssertEqual(RecapCloseOutPresentation.scrollProgress(offset: 0, contentHeight: 500, viewportHeight: 600), 1)     // fits → fully read
    }

    func testUnlockThresholdIsBottomMinus16() {
        // scrollable = 1000 - 600 = 400. Unlock at offset >= 384 (400 − 16).
        XCTAssertFalse(RecapCloseOutPresentation.isUnlocked(offset: 383, contentHeight: 1000, viewportHeight: 600))
        XCTAssertTrue(RecapCloseOutPresentation.isUnlocked(offset: 384, contentHeight: 1000, viewportHeight: 600))
        XCTAssertTrue(RecapCloseOutPresentation.isUnlocked(offset: 400, contentHeight: 1000, viewportHeight: 600))  // exact bottom
        XCTAssertFalse(RecapCloseOutPresentation.isUnlocked(offset: 100, contentHeight: 1000, viewportHeight: 600)) // mid-scroll locked
    }

    func testUnlockLockedWhenUnmeasured() {
        // Before layout (0 sizes) the sheet must stay LOCKED — never unlock early.
        XCTAssertFalse(RecapCloseOutPresentation.isUnlocked(offset: 0, contentHeight: 0, viewportHeight: 0))
        XCTAssertFalse(RecapCloseOutPresentation.isUnlocked(offset: 0, contentHeight: 1000, viewportHeight: 0))
    }

    func testUnlockShortContentIsImmediate() {
        // Content shorter than the viewport (nothing to read past) → unlocked.
        XCTAssertTrue(RecapCloseOutPresentation.isUnlocked(offset: 0, contentHeight: 500, viewportHeight: 600))
    }

    func testPercentLabelRounds() {
        XCTAssertEqual(RecapCloseOutPresentation.percentLabel(0), "0%")
        XCTAssertEqual(RecapCloseOutPresentation.percentLabel(0.5), "50%")
        XCTAssertEqual(RecapCloseOutPresentation.percentLabel(0.615), "62%")   // rounds
        XCTAssertEqual(RecapCloseOutPresentation.percentLabel(1), "100%")
        XCTAssertEqual(RecapCloseOutPresentation.percentLabel(1.5), "100%")    // clamps
    }

    func testIsValidRating() {
        XCTAssertFalse(RecapCloseOutPresentation.isValidRating(0))
        XCTAssertTrue(RecapCloseOutPresentation.isValidRating(1))
        XCTAssertTrue(RecapCloseOutPresentation.isValidRating(5))
        XCTAssertFalse(RecapCloseOutPresentation.isValidRating(6))
    }

    // MARK: - Required-rating gating (Close disabled without a 1–5)

    func testCloseDisabledUntilRated() {
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: StubCloseFlow())
        XCTAssertFalse(vm.canClose)     // unrated
        vm.pick(4)
        XCTAssertTrue(vm.canClose)
        XCTAssertEqual(vm.rating, 4)
    }

    func testPickIgnoresOutOfRange() {
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: StubCloseFlow())
        vm.pick(0)
        XCTAssertEqual(vm.rating, 0)
        vm.pick(9)
        XCTAssertEqual(vm.rating, 0)
        XCTAssertFalse(vm.canClose)
    }

    func testCloseNoOpWhenUnrated() async {
        let flow = StubCloseFlow()
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: flow)
        var dismissed = false
        await vm.close(onCleared: { dismissed = true })
        XCTAssertTrue(flow.closeCalls.isEmpty)   // never hit the endpoint
        XCTAssertFalse(vm.cleared)
        XCTAssertFalse(dismissed)
    }

    func testToggleThumbTogglesOff() {
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: StubCloseFlow())
        XCTAssertNil(vm.thumbs)
        vm.toggleThumb(true)
        XCTAssertEqual(vm.thumbs, true)
        vm.toggleThumb(false)
        XCTAssertEqual(vm.thumbs, false)
        vm.toggleThumb(false)      // re-tap clears
        XCTAssertNil(vm.thumbs)
    }

    // MARK: - Gate-clear + 409-as-cleared handling

    func testCloseClearsGateAndSendsThumbs() async {
        let flow = StubCloseFlow()
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: flow)
        vm.pick(5)
        vm.toggleThumb(true)
        var dismissed = false
        await vm.close(onCleared: { dismissed = true })
        XCTAssertEqual(flow.closeCalls.count, 1)
        XCTAssertEqual(flow.closeCalls.first?.rating, 5)
        XCTAssertEqual(flow.closeCalls.first?.thumbs, true)   // always sent
        XCTAssertTrue(vm.cleared)
        XCTAssertEqual(vm.toast, "Gate cleared.")
        XCTAssertTrue(dismissed)
        XCTAssertNil(vm.closeError)
    }

    func testReCloseConflictTreatedAsCleared() async {
        // 409 re-close = already closed → the gate is already clear, still dismiss.
        let flow = StubCloseFlow(throwStatus: 409)
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: flow)
        vm.pick(3)
        var dismissed = false
        await vm.close(onCleared: { dismissed = true })
        XCTAssertTrue(vm.cleared)
        XCTAssertEqual(vm.toast, "Gate cleared.")
        XCTAssertTrue(dismissed)
        XCTAssertNil(vm.closeError)
    }

    func testDefensive422RollsBack() async {
        // 422 shouldn't happen (the button gates on a valid rating) — recover.
        let flow = StubCloseFlow(throwStatus: 422)
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: flow)
        vm.pick(4)
        var dismissed = false
        await vm.close(onCleared: { dismissed = true })
        XCTAssertFalse(vm.cleared)
        XCTAssertEqual(vm.rating, 0)              // rolled back to re-tappable
        XCTAssertNotNil(vm.closeError)
        XCTAssertFalse(dismissed)
    }

    func testTransportErrorSurfacesRetryable() async {
        let flow = StubCloseFlow(throwStatus: 500)
        let vm = RecapCloseOutViewModel(sessionId: 5150, flow: flow)
        vm.pick(2)
        var dismissed = false
        await vm.close(onCleared: { dismissed = true })
        XCTAssertFalse(vm.cleared)
        XCTAssertNotNil(vm.closeError)
        XCTAssertFalse(dismissed)
    }
}
