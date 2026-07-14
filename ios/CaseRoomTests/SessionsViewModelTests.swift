/*
 * Purpose: Unit tests for SessionsViewModel — stubbed SessionsService +
 *          CalendarAdding proving accept/decline state transitions and
 *          non-fatal calendar-error handling.
 * Inputs: none (in-memory stub service/calendar).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubSessionsService: SessionsService {
    var proposalsResult: Result<[Proposal], Error> = .success([])
    var sessionsResult: Result<[SessionSummary], Error> = .success([])
    var acceptResult: Result<AcceptedSession, Error> = .success(
        AcceptedSession(accepted: true, sessionId: 1, sessionUrl: "https://example.com/s/1", icsUrl: "https://example.com/s/1.ics")
    )
    var declineError: Error?

    var recordedAcceptIds: [Int] = []
    var recordedAcceptTimes: [Date] = []
    var recordedDeclineIds: [Int] = []

    func proposals() async throws -> [Proposal] {
        try proposalsResult.get()
    }

    func sessions(scope: String) async throws -> [SessionSummary] {
        try sessionsResult.get()
    }

    func acceptProposal(id: Int, scheduledAt: Date) async throws -> AcceptedSession {
        recordedAcceptIds.append(id)
        recordedAcceptTimes.append(scheduledAt)
        return try acceptResult.get()
    }

    func declineProposal(id: Int) async throws {
        recordedDeclineIds.append(id)
        if let declineError { throw declineError }
    }
}

final class StubCalendarAdding: CalendarAdding {
    var addError: Error?
    var recordedTitles: [String] = []
    var recordedStartDates: [Date] = []
    var recordedNotes: [String?] = []

    func add(title: String, startDate: Date, notes: String?) async throws {
        recordedTitles.append(title)
        recordedStartDates.append(startDate)
        recordedNotes.append(notes)
        if let addError { throw addError }
    }
}

private enum TestError: Error { case boom }

final class SessionsViewModelTests: XCTestCase {
    private func makeProposal(id: Int, times: [Date] = [Date(timeIntervalSince1970: 1_800_000_000)]) -> Proposal {
        Proposal(
            id: id, fromName: "Bob Dev", fromRole: "interviewer", caseId: 5,
            caseTitle: "Widget Co", caseType: "Profitability", difficulty: "Medium",
            message: "Let's practice", proposedTimes: times, createdAt: Date()
        )
    }

    private func makeSession(id: Int, caseTitle: String) -> SessionSummary {
        SessionSummary(
            id: id, role: "candidate", otherUser: "Bob Dev", caseTitle: caseTitle,
            scheduledAt: Date(), state: "scheduled", endedAt: nil, grade: nil
        )
    }

    func testAcceptRemovesProposalReloadsUpcomingAndAddsToCalendar() async {
        let service = StubSessionsService()
        let proposal = makeProposal(id: 9)
        service.proposalsResult = .success([proposal])
        let newSession = makeSession(id: 42, caseTitle: "Widget Co")
        service.sessionsResult = .success([newSession])
        let calendar = StubCalendarAdding()
        let viewModel = SessionsViewModel(service: service, calendar: calendar)
        await viewModel.load()
        let chosenTime = proposal.proposedTimes[0]

        await viewModel.accept(proposal, at: chosenTime)

        XCTAssertTrue(viewModel.proposals.isEmpty)
        XCTAssertEqual(viewModel.upcoming, [newSession])
        XCTAssertEqual(service.recordedAcceptIds, [9])
        XCTAssertEqual(service.recordedAcceptTimes, [chosenTime])
        XCTAssertEqual(calendar.recordedTitles, ["Widget Co"])
        XCTAssertEqual(calendar.recordedStartDates, [chosenTime])
        XCTAssertEqual(calendar.recordedNotes, ["with Bob Dev"])
        XCTAssertNil(viewModel.calendarError)
    }

    func testDeclineRemovesProposalAndNeverTouchesCalendar() async {
        let service = StubSessionsService()
        let proposal = makeProposal(id: 11)
        service.proposalsResult = .success([proposal])
        let calendar = StubCalendarAdding()
        let viewModel = SessionsViewModel(service: service, calendar: calendar)
        await viewModel.load()

        await viewModel.decline(proposal)

        XCTAssertTrue(viewModel.proposals.isEmpty)
        XCTAssertEqual(service.recordedDeclineIds, [11])
        XCTAssertTrue(calendar.recordedTitles.isEmpty)
    }

    func testCalendarAddErrorIsCaughtAndDoesNotBlockAccept() async {
        let service = StubSessionsService()
        let proposal = makeProposal(id: 7)
        service.proposalsResult = .success([proposal])
        let calendar = StubCalendarAdding()
        calendar.addError = TestError.boom
        let viewModel = SessionsViewModel(service: service, calendar: calendar)
        await viewModel.load()
        let chosenTime = proposal.proposedTimes[0]

        await viewModel.accept(proposal, at: chosenTime)

        XCTAssertTrue(viewModel.proposals.isEmpty)
        XCTAssertEqual(service.recordedAcceptIds, [7])
        XCTAssertNotNil(viewModel.calendarError)
    }
}
