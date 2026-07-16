/*
 * Purpose: Unit tests for FreeNowViewModel — a stubbed AvailabilityService
 *          proving toggle-on sets free (60m per DF-3), toggle-off clears,
 *          refresh surfaces classmates, and every mutation writes the free-now
 *          snapshot while preserving streak/drill/next-session fields.
 * Inputs: none (in-memory stub service, injected snapshot hooks).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

private enum FreeNowTestError: Error { case boom }

private final class StubAvailabilityService: AvailabilityService {
    var availabilityResult: Result<AvailabilityStatus, Error>
    var setFreeResult: Result<AvailabilityStatus, Error>
    var clearError: Error?

    private(set) var setFreeMinutes: [Int] = []
    private(set) var clearCallCount = 0
    private(set) var availabilityCallCount = 0

    init(availabilityResult: Result<AvailabilityStatus, Error> = .success(AvailabilityStatus(freeUntil: nil, others: [])),
         setFreeResult: Result<AvailabilityStatus, Error> = .success(AvailabilityStatus(freeUntil: nil, others: []))) {
        self.availabilityResult = availabilityResult
        self.setFreeResult = setFreeResult
    }

    func availability() async throws -> AvailabilityStatus {
        availabilityCallCount += 1
        return try availabilityResult.get()
    }

    func setFree(minutes: Int) async throws -> AvailabilityStatus {
        setFreeMinutes.append(minutes)
        return try setFreeResult.get()
    }

    func clearFree() async throws {
        clearCallCount += 1
        if let clearError { throw clearError }
    }
}

// Reference box so injected value-capturing closures mutate shared state without
// tripping @escaping mutable-capture rules under the @MainActor view model.
private final class SnapshotCapture {
    var written: WidgetSnapshot?
    var reloadCount = 0
}

final class FreeNowViewModelTests: XCTestCase {
    private func freeUser(_ id: Int, _ name: String, minutes: Double = 60) -> FreeUser {
        FreeUser(userId: id, name: name, freeUntil: Date(timeIntervalSinceNow: minutes * 60))
    }

    @MainActor
    private func makeViewModel(
        service: StubAvailabilityService,
        capture: SnapshotCapture = SnapshotCapture(),
        current: WidgetSnapshot? = nil
    ) -> FreeNowViewModel {
        FreeNowViewModel(
            service: service,
            readSnapshot: { current },
            writeSnapshot: { capture.written = $0 },
            reloadWidgets: { capture.reloadCount += 1 }
        )
    }

    @MainActor
    func testToggleOnSetsFreeForSixtyMinutesAndSurfacesOthers() async {
        let future = Date(timeIntervalSinceNow: 3600)
        let service = StubAvailabilityService(
            setFreeResult: .success(AvailabilityStatus(freeUntil: future, others: [freeUser(7, "Bob Dev")]))
        )
        let capture = SnapshotCapture()
        let viewModel = makeViewModel(service: service, capture: capture)

        await viewModel.toggle()

        XCTAssertEqual(service.setFreeMinutes, [60])
        XCTAssertTrue(viewModel.isFree)
        XCTAssertEqual(viewModel.freeUntil, future)
        XCTAssertEqual(viewModel.others.map(\.userId), [7])
        XCTAssertEqual(capture.written?.freeUntil, future)
        XCTAssertEqual(capture.reloadCount, 1)
    }

    @MainActor
    func testToggleOffClearsFreeAndPreservesStreakSnapshotFields() async {
        let future = Date(timeIntervalSinceNow: 3600)
        let service = StubAvailabilityService(
            setFreeResult: .success(AvailabilityStatus(freeUntil: future, others: []))
        )
        let current = WidgetSnapshot(
            streakDays: 4, drillDoneToday: true, nextSessionTitle: "Widget Co",
            nextSessionOther: "Bob Dev", nextSessionAt: nil, freeUntil: future,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let capture = SnapshotCapture()
        let viewModel = makeViewModel(service: service, capture: capture, current: current)
        await viewModel.toggle()               // on
        XCTAssertTrue(viewModel.isFree)

        await viewModel.toggle()               // off

        XCTAssertEqual(service.clearCallCount, 1)
        XCTAssertFalse(viewModel.isFree)
        XCTAssertNil(viewModel.freeUntil)
        // The free-now writer clears freeUntil but carries the other fields forward.
        XCTAssertNil(capture.written?.freeUntil)
        XCTAssertEqual(capture.written?.streakDays, 4)
        XCTAssertEqual(capture.written?.drillDoneToday, true)
        XCTAssertEqual(capture.written?.nextSessionTitle, "Widget Co")
        XCTAssertEqual(capture.written?.nextSessionOther, "Bob Dev")
    }

    @MainActor
    func testRefreshLoadsClassmatesAndOwnFreeUntil() async {
        let future = Date(timeIntervalSinceNow: 1800)
        let service = StubAvailabilityService(
            availabilityResult: .success(AvailabilityStatus(
                freeUntil: future, others: [freeUser(3, "Cara"), freeUser(9, "Dan")]
            ))
        )
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh()

        XCTAssertEqual(service.availabilityCallCount, 1)
        XCTAssertTrue(viewModel.isFree)
        XCTAssertEqual(viewModel.freeUntil, future)
        XCTAssertEqual(viewModel.others.map(\.name), ["Cara", "Dan"])
    }

    @MainActor
    func testRefreshWithNoAvailabilityLeavesNotFree() async {
        let service = StubAvailabilityService(
            availabilityResult: .success(AvailabilityStatus(freeUntil: nil, others: []))
        )
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh()

        XCTAssertFalse(viewModel.isFree)
        XCTAssertNil(viewModel.freeUntil)
        XCTAssertTrue(viewModel.others.isEmpty)
    }

    @MainActor
    func testToggleOnFailureSetsErrorAndStaysNotFree() async {
        let service = StubAvailabilityService(setFreeResult: .failure(FreeNowTestError.boom))
        let capture = SnapshotCapture()
        let viewModel = makeViewModel(service: service, capture: capture)

        await viewModel.toggle()

        XCTAssertFalse(viewModel.isFree)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(capture.written)          // no snapshot write on failure
    }

    @MainActor
    func testErrorMessageClearsOnNextSuccessfulRefresh() async {
        let service = StubAvailabilityService(availabilityResult: .failure(FreeNowTestError.boom))
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh()
        XCTAssertNotNil(viewModel.errorMessage)   // set on failure (now rendered by TodayView)

        service.availabilityResult = .success(AvailabilityStatus(freeUntil: nil, others: []))
        await viewModel.refresh()
        XCTAssertNil(viewModel.errorMessage)      // cleared on the next successful action
    }
}
