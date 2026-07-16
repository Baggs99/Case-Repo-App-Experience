/*
 * Purpose: Unit tests for TodayViewModel — stubbed TodayService proving the
 *          soonest-upcoming session, streak, and finalized count surface
 *          correctly, and that a nil nextSession drives the empty state.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubTodayService: TodayService {
    var dashboardResult: Result<DashboardStats, Error> = .success(
        DashboardStats(sessionsFinalized: 0, streakWeeks: 0, nextSession: nil, streakDays: nil, drillDoneToday: nil)
    )

    func dashboard() async throws -> DashboardStats {
        try dashboardResult.get()
    }
}

private enum TestError: Error { case boom }

final class TodayViewModelTests: XCTestCase {
    private func makeSession(id: Int, caseTitle: String) -> SessionSummary {
        SessionSummary(
            id: id, role: "candidate", otherUser: "Bob Dev", caseTitle: caseTitle,
            scheduledAt: Date(timeIntervalSinceNow: 3600), state: "scheduled", endedAt: nil, grade: nil
        )
    }

    func testLoadSurfacesNextSessionStreakAndFinalized() async {
        let service = StubTodayService()
        let nextSession = makeSession(id: 3, caseTitle: "Widget Co")
        service.dashboardResult = .success(
            DashboardStats(sessionsFinalized: 5, streakWeeks: 2, nextSession: nextSession, streakDays: nil, drillDoneToday: nil)
        )
        let viewModel = TodayViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.nextSession, nextSession)
        XCTAssertEqual(viewModel.streakWeeks, 2)
        XCTAssertEqual(viewModel.sessionsFinalized, 5)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadWithNoNextSessionDrivesEmptyStateButStillSurfacesStreakAndFinalized() async {
        let service = StubTodayService()
        service.dashboardResult = .success(
            DashboardStats(sessionsFinalized: 7, streakWeeks: 4, nextSession: nil, streakDays: nil, drillDoneToday: nil)
        )
        let viewModel = TodayViewModel(service: service)

        await viewModel.load()

        XCTAssertNil(viewModel.nextSession)
        XCTAssertEqual(viewModel.streakWeeks, 4)
        XCTAssertEqual(viewModel.sessionsFinalized, 7)
    }

    func testLoadFailureSetsErrorMessage() async {
        let service = StubTodayService()
        service.dashboardResult = .failure(TestError.boom)
        let viewModel = TodayViewModel(service: service)

        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.nextSession)
    }
}
