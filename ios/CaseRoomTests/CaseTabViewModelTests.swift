/*
 * Purpose: Unit tests for CaseTabViewModel — stubbed CaseTabService +
 *          CalendarAdding proving proposal bucketing (received-pending vs
 *          sent-pending/countered), gateRecap/nextUp selection, and the
 *          accept/decline/counter/addToCalendar action paths (incl. the
 *          CaseGateError.blockedByRecap gate). Mirrors
 *          SessionsViewModelTests.swift's stub/spy style.
 * Inputs: none (in-memory stub service/calendar).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubCaseTabService: CaseTabService {
    var recapsResult: Result<[RecapItem], Error> = .success([])
    var proposalsResult: Result<[Proposal], Error> = .success([])
    var upcomingResult: Result<[SessionSummary], Error> = .success([])
    var recentResult: Result<[SessionSummary], Error> = .success([])
    var acceptResult: Result<AcceptedSession, Error> = .success(
        AcceptedSession(accepted: true, sessionId: 1, sessionUrl: "https://example.com/s/1", icsUrl: "https://example.com/s/1.ics")
    )
    var declineError: Error?
    var counterError: Error?

    private(set) var recordedAcceptIds: [Int] = []
    private(set) var recordedAcceptTimes: [Date] = []
    private(set) var recordedDeclineIds: [Int] = []
    private(set) var recordedCounterIds: [Int] = []
    private(set) var recordedCounterTimes: [[Date]] = []

    func recaps() async throws -> [RecapItem] { try recapsResult.get() }
    func proposals() async throws -> [Proposal] { try proposalsResult.get() }

    func sessions(scope: String) async throws -> [SessionSummary] {
        switch scope {
        case "upcoming": return try upcomingResult.get()
        case "recent": return try recentResult.get()
        default: return []
        }
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

    func counterProposal(id: Int, times: [Date]) async throws {
        recordedCounterIds.append(id)
        recordedCounterTimes.append(times)
        if let counterError { throw counterError }
    }
}

final class CaseTabViewModelTests: XCTestCase {
    private func makeProposal(
        id: Int, direction: String, state: String, caseTitle: String? = "Widget Co", fromName: String = "Bob Dev"
    ) -> Proposal {
        Proposal(
            id: id, fromName: fromName, fromRole: "interviewer", caseId: 5, caseTitle: caseTitle,
            caseType: "Profitability", difficulty: "Medium", message: nil,
            proposedTimes: [Date(timeIntervalSince1970: 1_800_000_000)], createdAt: Date(),
            direction: direction, state: state
        )
    }

    private func makeRecap(sessionId: Int, viewedAt: Date?) -> RecapItem {
        RecapItem(
            sessionId: sessionId, caseId: 6, caseTitle: "Ski resort: revenue up, profit down",
            interviewerName: "T. Becker", grade: 4.1, finalizedAt: Date(), viewedAt: viewedAt
        )
    }

    private func makeSession(
        id: Int, scheduledAt: Date?, caseTitle: String = "Widget Co", otherUser: String = "Bob Dev"
    ) -> SessionSummary {
        SessionSummary(
            id: id, role: "candidate", otherUser: otherUser, caseTitle: caseTitle,
            scheduledAt: scheduledAt, state: "scheduled", endedAt: nil, grade: nil
        )
    }

    // MARK: - Proposal bucketing

    func testLoadBucketsProposalsByDirectionAndState() async {
        let service = StubCaseTabService()
        let received = makeProposal(id: 1, direction: "received", state: "pending")
        let receivedAccepted = makeProposal(id: 2, direction: "received", state: "accepted")
        let sentPending = makeProposal(id: 3, direction: "sent", state: "pending")
        let sentCountered = makeProposal(id: 4, direction: "sent", state: "countered")
        let sentDeclined = makeProposal(id: 5, direction: "sent", state: "declined")
        service.proposalsResult = .success([received, receivedAccepted, sentPending, sentCountered, sentDeclined])
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        await vm.load()

        XCTAssertEqual(vm.pendingReceived.map(\.id), [1])
        XCTAssertEqual(Set(vm.sentAwaiting.map(\.id)), Set([3, 4]))
    }

    // MARK: - gateRecap

    func testGateRecapIsFirstUnviewedRecap() async {
        let service = StubCaseTabService()
        let viewed = makeRecap(sessionId: 1, viewedAt: Date())
        let unviewed = makeRecap(sessionId: 2, viewedAt: nil)
        let alsoUnviewed = makeRecap(sessionId: 3, viewedAt: nil)
        service.recapsResult = .success([viewed, unviewed, alsoUnviewed])
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        await vm.load()

        XCTAssertEqual(vm.gateRecap?.sessionId, 2)
    }

    // MARK: - nextUp / upcoming

    func testNextUpIsSoonestUpcomingSession() async {
        let service = StubCaseTabService()
        let later = makeSession(id: 10, scheduledAt: Date().addingTimeInterval(3600 * 5))
        let soonest = makeSession(id: 11, scheduledAt: Date().addingTimeInterval(3600))
        let latest = makeSession(id: 12, scheduledAt: Date().addingTimeInterval(3600 * 10))
        service.upcomingResult = .success([later, soonest, latest])
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        await vm.load()

        XCTAssertEqual(vm.nextUp?.id, 11)
        XCTAssertEqual(Set(vm.upcoming.map(\.id)), Set([10, 12]))
    }

    // MARK: - accept

    func testAcceptRemovesFromPendingReceivedRefreshesUpcomingAndAddsToCalendarOnce() async {
        let service = StubCaseTabService()
        let proposal = makeProposal(id: 20, direction: "received", state: "pending")
        service.proposalsResult = .success([proposal])
        let refreshedSession = makeSession(id: 30, scheduledAt: Date().addingTimeInterval(3600))
        service.upcomingResult = .success([refreshedSession])
        let calendar = StubCalendarAdding()
        let vm = CaseTabViewModel(service: service, calendar: calendar)
        await vm.load()
        let chosenTime = Date().addingTimeInterval(7200)

        await vm.accept(proposal, at: chosenTime)

        XCTAssertTrue(vm.pendingReceived.isEmpty)
        XCTAssertEqual(vm.nextUp?.id, 30)
        XCTAssertEqual(service.recordedAcceptIds, [20])
        XCTAssertEqual(service.recordedAcceptTimes, [chosenTime])
        XCTAssertEqual(calendar.recordedTitles, ["Widget Co"])
        XCTAssertEqual(calendar.recordedNotes, ["with Bob Dev"])
        XCTAssertNil(vm.calendarError)
    }

    func testAcceptCatchingBlockedByRecapSetsGateAndSkipsCalendar() async {
        let service = StubCaseTabService()
        let proposal = makeProposal(id: 21, direction: "received", state: "pending")
        service.proposalsResult = .success([proposal])
        service.acceptResult = .failure(CaseGateError.blockedByRecap(555))
        let calendar = StubCalendarAdding()
        let vm = CaseTabViewModel(service: service, calendar: calendar)
        await vm.load()

        await vm.accept(proposal, at: Date())

        XCTAssertEqual(vm.gatedRecapSessionID, 555)
        XCTAssertTrue(calendar.recordedTitles.isEmpty)
        XCTAssertEqual(vm.pendingReceived.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - decline

    func testDeclineRemovesFromPendingReceived() async {
        let service = StubCaseTabService()
        let proposal = makeProposal(id: 22, direction: "received", state: "pending")
        service.proposalsResult = .success([proposal])
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())
        await vm.load()

        await vm.decline(proposal)

        XCTAssertTrue(vm.pendingReceived.isEmpty)
        XCTAssertEqual(service.recordedDeclineIds, [22])
    }

    // MARK: - counter

    func testCounterCallsServiceWithTimes() async {
        let service = StubCaseTabService()
        let proposal = makeProposal(id: 23, direction: "received", state: "pending")
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())
        let times = [Date(), Date().addingTimeInterval(3600)]

        await vm.counter(proposal, times: times)

        XCTAssertEqual(service.recordedCounterIds, [23])
        XCTAssertEqual(service.recordedCounterTimes, [times])
    }

    // MARK: - addToCalendar

    func testAddToCalendarGuardsNilScheduledAt() async {
        let calendar = StubCalendarAdding()
        let vm = CaseTabViewModel(service: StubCaseTabService(), calendar: calendar)
        let session = makeSession(id: 40, scheduledAt: nil)

        await vm.addToCalendar(session)

        XCTAssertTrue(calendar.recordedTitles.isEmpty)
    }

    func testAddToCalendarAddsWhenScheduledAtPresent() async {
        let calendar = StubCalendarAdding()
        let vm = CaseTabViewModel(service: StubCaseTabService(), calendar: calendar)
        let at = Date().addingTimeInterval(3600)
        let session = makeSession(id: 41, scheduledAt: at, caseTitle: "Widget Co", otherUser: "Bob")

        await vm.addToCalendar(session)

        XCTAssertEqual(calendar.recordedTitles, ["Widget Co"])
        XCTAssertEqual(calendar.recordedNotes, ["with Bob"])
        XCTAssertEqual(calendar.recordedStartDates, [at])
    }
}
