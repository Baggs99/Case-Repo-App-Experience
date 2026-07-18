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
    // MARK: F3 T6 — availability()/createNowInvite() added to CaseTabService
    // for the tablet tray's LIVE NOW board.
    var availabilityResult: Result<AvailabilityStatus, Error> = .success(AvailabilityStatus(freeUntil: nil, others: []))
    var pingError: Error?

    private(set) var recordedAcceptIds: [Int] = []
    private(set) var recordedAcceptTimes: [Date] = []
    private(set) var recordedDeclineIds: [Int] = []
    private(set) var recordedCounterIds: [Int] = []
    private(set) var recordedCounterTimes: [[Date]] = []
    private(set) var recordedPingUserIds: [Int] = []

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

    func availability() async throws -> AvailabilityStatus { try availabilityResult.get() }

    func createNowInvite(toUserId: Int) async throws {
        recordedPingUserIds.append(toUserId)
        if let pingError { throw pingError }
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

    // MARK: - F3 T6 — tablet tray's LIVE NOW board (availability + ping)

    func testLoadPopulatesLiveNowFromAvailabilityOthers() async {
        let service = StubCaseTabService()
        let freeUntil = Date().addingTimeInterval(45 * 60)
        service.availabilityResult = .success(
            AvailabilityStatus(freeUntil: nil, others: [FreeUser(userId: 501, name: "S. Park", freeUntil: freeUntil)])
        )
        let fixedNow = Date()
        let vm = CaseTabViewModel(
            service: service, calendar: StubCalendarAdding(), now: { fixedNow }, schools: [501: "Wharton"]
        )

        await vm.load()

        XCTAssertEqual(vm.liveNow.count, 1)
        XCTAssertEqual(vm.liveNow.first?.name, "S. Park")
        XCTAssertEqual(vm.liveNow.first?.school, "Wharton")
        XCTAssertEqual(vm.liveNow.first?.minutesFree, 45)
    }

    func testLoadLeavesLiveNowEmptyAndDoesNotFailWhenAvailabilityErrors() async {
        struct Boom: Error {}
        let service = StubCaseTabService()
        service.availabilityResult = .failure(Boom())
        service.upcomingResult = .success([makeSession(id: 50, scheduledAt: Date())])
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        await vm.load()

        XCTAssertTrue(vm.liveNow.isEmpty)
        // The phone spine's data still loads fine — an availability failure
        // is non-fatal (F3 T6: unused by the phone, best-effort on tablet).
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.nextUp?.id, 50)
    }

    func testPingSendsNowInviteAndReturnsTrueOnSuccess() async {
        let service = StubCaseTabService()
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        let result = await vm.ping(userId: 501)

        XCTAssertTrue(result)
        XCTAssertEqual(service.recordedPingUserIds, [501])
        XCTAssertNil(vm.errorMessage)
    }

    func testPingReturnsFalseAndSetsErrorMessageOnFailure() async {
        struct Boom: Error {}
        let service = StubCaseTabService()
        service.pingError = Boom()
        let vm = CaseTabViewModel(service: service, calendar: StubCalendarAdding())

        let result = await vm.ping(userId: 501)

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - F3 T6 — July-17 tablet fixture (Decisions §7 day-advance)

    func testTabletFixtureClearsGateAndKeepsBeckerPendingUntilAccepted() async {
        let vm = CaseFixtures.makeTabletViewModel()

        await vm.load()

        // Gate cleared: last night's Nordic recap is already rated 5/5.
        XCTAssertNil(vm.gateRecap)
        // T. Becker's dental-roll-up ask + S. Park's tonight ask, same ids as
        // the phone's July-16 persona for continuity.
        XCTAssertEqual(Set(vm.pendingReceived.map(\.id)), Set([201, 202]))
        // Nordic already happened last night — it's in history (7.2), not upcoming.
        XCTAssertTrue(vm.history.contains { $0.otherUser == "M. Lindqvist" && $0.grade == 7.2 })
        XCTAssertFalse(vm.upcoming.contains { $0.otherUser == "M. Lindqvist" } || vm.nextUp?.otherUser == "M. Lindqvist")
    }
}
