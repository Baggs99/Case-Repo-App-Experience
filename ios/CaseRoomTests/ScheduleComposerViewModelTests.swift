/*
 * Purpose: Unit tests for ScheduleComposerViewModel — a stubbed ScheduleService
 *          proves load() populates the WHO chips + the Request-row rec title,
 *          the WHEN quick-pick time semantics (now / +1h / Tonight 8pm today-vs-
 *          tomorrow / pickTime), send()'s scheduled-proposal args (case-less
 *          "Interviewer decides" → caseId nil vs Request → rec.caseId, from_role
 *          "candidate"), the canSend gating, and the success toast/sent flag —
 *          all without a real network call.
 * Inputs: none (in-memory stub service + a fixed clock/calendar).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubScheduleService: ScheduleService {
    var connectionsResult: [Connection] = []
    var recommendationsResult: [Recommendation] = []
    var connectionsError: Error?
    var recommendationsError: Error?
    var sendError: Error?

    private(set) var sentCalls: [(toUserId: Int, caseId: Int?, fromRole: String, proposedTimes: [Date])] = []

    func connections() async throws -> [Connection] {
        if let connectionsError { throw connectionsError }
        return connectionsResult
    }

    func recommendations(exclude: [Int]) async throws -> [Recommendation] {
        if let recommendationsError { throw recommendationsError }
        return recommendationsResult
    }

    func sendScheduledProposal(toUserId: Int, caseId: Int?, fromRole: String, proposedTimes: [Date]) async throws {
        sentCalls.append((toUserId, caseId, fromRole, proposedTimes))
        if let sendError { throw sendError }
    }
}

@MainActor
final class ScheduleComposerViewModelTests: XCTestCase {
    private static func connection(_ id: Int, _ name: String) -> Connection {
        Connection(userId: id, displayName: name, photoUrl: nil, bio: nil, freeNow: false, swapInvitePending: false)
    }

    private static let evChargingRec = Recommendation(
        caseId: 8, title: "EV charging — size the German market",
        caseType: "Market Sizing", difficulty: nil, why: nil, rule: nil
    )

    private func makeViewModel(
        service: StubScheduleService,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) -> ScheduleComposerViewModel {
        ScheduleComposerViewModel(service: service, now: now, calendar: calendar)
    }

    // MARK: - load()

    func testLoadPopulatesWhoChipsAndRequestRec() async {
        let stub = StubScheduleService()
        stub.connectionsResult = [
            Self.connection(501, "S. Park"),
            Self.connection(601, "T. Becker"),
            Self.connection(701, "M. Lindqvist"),
        ]
        stub.recommendationsResult = [Self.evChargingRec]
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.who.map(\.id), [501, 601, 701])
        XCTAssertEqual(viewModel.who.map(\.name), ["S. Park", "T. Becker", "M. Lindqvist"])
        // caseOptions: [.interviewerDecides, .request(top rec)]
        XCTAssertEqual(viewModel.caseOptions.count, 2)
        XCTAssertEqual(viewModel.caseOptions.first, .interviewerDecides)
        XCTAssertEqual(viewModel.caseOptions.last?.label, "Request: EV charging — size the German market")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadTakesOnlyTopRecommendation() async {
        let stub = StubScheduleService()
        stub.recommendationsResult = [
            Self.evChargingRec,
            Recommendation(caseId: 9, title: "Second rec", caseType: nil, difficulty: nil, why: nil, rule: nil),
        ]
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.caseOptions.count, 2)   // interviewerDecides + one request
        XCTAssertEqual(viewModel.caseOptions.last, .request(Self.evChargingRec))
    }

    func testLoadFailureSetsErrorMessage() async {
        let stub = StubScheduleService()
        stub.connectionsError = APIError.server(500)
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.who.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - proposedTimes() WHEN semantics

    func testProposedTimesNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = makeViewModel(service: StubScheduleService(), now: { now })
        viewModel.selectedWhen = .now

        XCTAssertEqual(viewModel.proposedTimes(), [now])
    }

    func testProposedTimesOneHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = makeViewModel(service: StubScheduleService(), now: { now })
        viewModel.selectedWhen = .oneHour

        XCTAssertEqual(viewModel.proposedTimes(), [now.addingTimeInterval(3600)])
    }

    func testProposedTimesPickTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let picked = Date(timeIntervalSince1970: 2_000_000)
        let viewModel = makeViewModel(service: StubScheduleService(), now: { now })
        viewModel.selectedWhen = .pickTime
        viewModel.pickTime = picked

        XCTAssertEqual(viewModel.proposedTimes(), [picked])
    }

    func testProposedTimesEmptyWhenNothingPicked() {
        let viewModel = makeViewModel(service: StubScheduleService())
        XCTAssertTrue(viewModel.proposedTimes().isEmpty)
    }

    // MARK: - Tonight 8pm (today when before 20:00, tomorrow when past)

    func testTonight8pmTodayWhenBefore8pm() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-07-17 14:00 local — before 20:00, so tonight 20:00 same day.
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 14))!
        let result = ScheduleComposerViewModel.tonight8pm(from: now, calendar: calendar)

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 17)      // same day
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 0)
    }

    func testTonight8pmTomorrowWhenPast8pm() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-07-17 21:30 local — past 20:00, so 20:00 rolls to tomorrow.
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 21, minute: 30))!
        let result = ScheduleComposerViewModel.tonight8pm(from: now, calendar: calendar)

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(comps.day, 18)      // next day
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 0)
    }

    func testProposedTimesTonight8pmUsesTonightHelper() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 14))!
        let viewModel = makeViewModel(service: StubScheduleService(), now: { now }, calendar: calendar)
        viewModel.selectedWhen = .tonight8pm

        XCTAssertEqual(viewModel.proposedTimes(), [ScheduleComposerViewModel.tonight8pm(from: now, calendar: calendar)])
    }

    // MARK: - send()

    func testSendInterviewerDecidesPassesNilCaseId() async {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let stub = StubScheduleService()
        let viewModel = makeViewModel(service: stub, now: { now })
        viewModel.selectedWhoID = 501
        viewModel.selectedWhen = .now
        viewModel.selectedCase = .interviewerDecides

        await viewModel.send()

        XCTAssertEqual(stub.sentCalls.count, 1)
        let call = stub.sentCalls[0]
        XCTAssertEqual(call.toUserId, 501)
        XCTAssertNil(call.caseId)               // "Interviewer decides" → case-less
        XCTAssertEqual(call.fromRole, "candidate")
        XCTAssertEqual(call.proposedTimes, [now])
        XCTAssertTrue(viewModel.sent)
        XCTAssertEqual(viewModel.toastMessage, "Proposal sent")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSendRequestPassesRecCaseId() async {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let stub = StubScheduleService()
        let viewModel = makeViewModel(service: stub, now: { now })
        viewModel.selectedWhoID = 701
        viewModel.selectedWhen = .oneHour
        viewModel.selectedCase = .request(Self.evChargingRec)

        await viewModel.send()

        XCTAssertEqual(stub.sentCalls.count, 1)
        let call = stub.sentCalls[0]
        XCTAssertEqual(call.toUserId, 701)
        XCTAssertEqual(call.caseId, 8)          // Request → rec.caseId
        XCTAssertEqual(call.fromRole, "candidate")
        XCTAssertEqual(call.proposedTimes, [now.addingTimeInterval(3600)])
        XCTAssertTrue(viewModel.sent)
    }

    func testSendGuardsWhenIncomplete() async {
        let stub = StubScheduleService()
        let viewModel = makeViewModel(service: stub)
        viewModel.selectedWhoID = nil           // no WHO chosen
        viewModel.selectedWhen = .now
        viewModel.selectedCase = .interviewerDecides

        await viewModel.send()

        XCTAssertTrue(stub.sentCalls.isEmpty)   // never called
        XCTAssertFalse(viewModel.sent)
    }

    func testSendFailureSetsErrorMessageAndNotSent() async {
        let stub = StubScheduleService()
        stub.sendError = APIError.server(500)
        let viewModel = makeViewModel(service: stub)
        viewModel.selectedWhoID = 501
        viewModel.selectedWhen = .now
        viewModel.selectedCase = .interviewerDecides

        await viewModel.send()

        XCTAssertFalse(viewModel.sent)
        XCTAssertNil(viewModel.toastMessage)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - canSend gating

    func testCanSendRequiresAllThreeSelections() {
        let viewModel = makeViewModel(service: StubScheduleService())
        XCTAssertFalse(viewModel.canSend)

        viewModel.selectedWhoID = 501
        XCTAssertFalse(viewModel.canSend)

        viewModel.selectedWhen = .now
        XCTAssertFalse(viewModel.canSend)

        viewModel.selectedCase = .interviewerDecides
        XCTAssertTrue(viewModel.canSend)
    }
}
