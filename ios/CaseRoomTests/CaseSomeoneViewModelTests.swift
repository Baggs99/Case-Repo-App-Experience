/*
 * Purpose: Unit tests for CaseSomeoneViewModel — a stubbed CaseSomeoneService
 *          proves load()'s open-invite filtering (received + candidate +
 *          pending only) and interviewer-log line, the pure code parser (both
 *          the caseroom:// URL and a bare code), and scanResult()'s pairClaim
 *          path (success → claimedSessionID; blockedByRecap → gatedRecapSessionID)
 *          — all without a real network call.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubCaseSomeoneService: CaseSomeoneService {
    var proposalsResult: Result<[Proposal], Error> = .success([])
    var recentResult: Result<[SessionSummary], Error> = .success([])
    var pairClaimResult: Result<Int, Error> = .success(999)

    // Records the SHORT CODES claimed (proves the short-code wire path is used,
    // not the token path — a plain string check wouldn't catch the wrong key).
    private(set) var recordedShortCodes: [String] = []

    func proposals() async throws -> [Proposal] { try proposalsResult.get() }

    func sessions(scope: String) async throws -> [SessionSummary] {
        scope == "recent" ? try recentResult.get() : []
    }

    func pairClaim(shortCode: String) async throws -> Int {
        recordedShortCodes.append(shortCode)
        return try pairClaimResult.get()
    }
}

@MainActor
final class CaseSomeoneViewModelTests: XCTestCase {
    private func proposal(
        id: Int, fromName: String, fromRole: String, direction: String, state: String,
        proposedTimes: [Date] = [Date(timeIntervalSince1970: 1_800_000_000)]
    ) -> Proposal {
        Proposal(
            id: id, fromName: fromName, fromRole: fromRole, caseId: nil, caseTitle: nil,
            caseType: nil, difficulty: nil, message: nil, proposedTimes: proposedTimes,
            createdAt: Date(), direction: direction, state: state
        )
    }

    private func makeViewModel(
        service: StubCaseSomeoneService,
        prefillCaseId: Int? = nil,
        prefillCaseTitle: String? = nil,
        now: @escaping () -> Date = { Date() },
        feedbackAvg: Double? = nil
    ) -> CaseSomeoneViewModel {
        CaseSomeoneViewModel(
            prefillCaseId: prefillCaseId, prefillCaseTitle: prefillCaseTitle,
            service: service, now: now, calendar: .current, feedbackAvg: feedbackAvg
        )
    }

    // MARK: - openInvites filtering

    func testOpenInvitesKeepsOnlyReceivedCandidatePending() {
        let proposals = [
            proposal(id: 1, fromName: "S. Park", fromRole: "candidate", direction: "received", state: "pending"),
            // Excluded: interviewer-role received (they offer to interview you).
            proposal(id: 2, fromName: "T. Becker", fromRole: "interviewer", direction: "received", state: "pending"),
            // Excluded: candidate but sent (you asked them).
            proposal(id: 3, fromName: "A. Osei", fromRole: "candidate", direction: "sent", state: "pending"),
            // Excluded: candidate + received but not pending.
            proposal(id: 4, fromName: "J. Okafor", fromRole: "candidate", direction: "received", state: "accepted"),
        ]
        let invites = CaseSomeoneViewModel.openInvites(from: proposals)
        XCTAssertEqual(invites.map(\.id), [1])
    }

    func testLoadPopulatesOpenInviteCountAndFlag() async {
        let stub = StubCaseSomeoneService()
        stub.proposalsResult = .success([
            proposal(id: 1, fromName: "S. Park", fromRole: "candidate", direction: "received", state: "pending"),
            proposal(id: 2, fromName: "T. Becker", fromRole: "interviewer", direction: "received", state: "pending"),
        ])
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.openInviteCount, 1)
        XCTAssertTrue(viewModel.hasNew)
        XCTAssertNotNil(viewModel.firstInviteLine)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadNoInvitesClearsNewFlag() async {
        let stub = StubCaseSomeoneService()
        stub.proposalsResult = .success([
            proposal(id: 2, fromName: "T. Becker", fromRole: "interviewer", direction: "received", state: "pending"),
        ])
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.openInviteCount, 0)
        XCTAssertFalse(viewModel.hasNew)
        XCTAssertNil(viewModel.firstInviteLine)
    }

    func testLoadFailureSetsErrorMessage() async {
        let stub = StubCaseSomeoneService()
        stub.proposalsResult = .failure(APIError.server(500))
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Invite line

    func testInviteLineTodayReadsTonight() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        let time = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now)!
        let invite = proposal(
            id: 1, fromName: "S. Park", fromRole: "candidate", direction: "received", state: "pending",
            proposedTimes: [time]
        )
        let line = CaseSomeoneViewModel.inviteLine(for: invite, now: now, calendar: calendar)
        XCTAssertEqual(line, "S. Park asks you to interview · tonight 21:30")
    }

    // MARK: - Interviewer log

    func testInterviewerLogCountsInterviewerSessionsThisMonthWithAvg() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            SessionSummary(id: 1, role: "interviewer", otherUser: "X", caseTitle: "A",
                           scheduledAt: nil, state: "done", endedAt: now, grade: 4.8),
            SessionSummary(id: 2, role: "interviewer", otherUser: "Y", caseTitle: "B",
                           scheduledAt: nil, state: "done", endedAt: now, grade: 4.6),
            // Excluded: candidate-role session this month.
            SessionSummary(id: 3, role: "candidate", otherUser: "Z", caseTitle: "C",
                           scheduledAt: nil, state: "done", endedAt: now, grade: 3.0),
        ]
        let line = CaseSomeoneViewModel.interviewerLogLine(
            from: sessions, now: now, calendar: .current, feedbackAvg: 4.7
        )
        XCTAssertEqual(line, "2 cased this month · 4.7 avg feedback quality")
    }

    func testInterviewerLogOmitsAvgWhenNoFeedbackData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            SessionSummary(id: 1, role: "interviewer", otherUser: "X", caseTitle: "A",
                           scheduledAt: nil, state: "done", endedAt: now, grade: nil),
        ]
        let line = CaseSomeoneViewModel.interviewerLogLine(
            from: sessions, now: now, calendar: .current, feedbackAvg: nil
        )
        XCTAssertEqual(line, "1 cased this month")
    }

    // MARK: - parseCode

    func testParseCodeFromDeepLinkURL() {
        XCTAssertEqual(CaseSomeoneViewModel.parseCode("caseroom://pair?code=ABC123"), "ABC123")
    }

    func testParseCodeFromBareCode() {
        XCTAssertEqual(CaseSomeoneViewModel.parseCode("ABC123"), "ABC123")
    }

    func testParseCodeTrimsWhitespace() {
        XCTAssertEqual(CaseSomeoneViewModel.parseCode("  K7Q-4TN \n"), "K7Q-4TN")
    }

    func testParseCodeRejectsEmpty() {
        XCTAssertNil(CaseSomeoneViewModel.parseCode("   "))
    }

    func testParseCodeRejectsCaseroomURLWithoutCode() {
        XCTAssertNil(CaseSomeoneViewModel.parseCode("caseroom://pair"))
    }

    // MARK: - scanResult

    func testScanResultParsesDeepLinkAndClaimsWithShortCode() async {
        let stub = StubCaseSomeoneService()
        stub.pairClaimResult = .success(555)
        let viewModel = makeViewModel(service: stub)

        await viewModel.scanResult("caseroom://pair?code=ABC123")

        // The parsed code goes through the SHORT-CODE claim path, not token.
        XCTAssertEqual(stub.recordedShortCodes, ["ABC123"])
        XCTAssertEqual(viewModel.claimedSessionID, 555)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testScanResultParsesBareCodeAndClaimsWithShortCode() async {
        let stub = StubCaseSomeoneService()
        stub.pairClaimResult = .success(777)
        let viewModel = makeViewModel(service: stub)

        await viewModel.scanResult("ABC123")

        XCTAssertEqual(stub.recordedShortCodes, ["ABC123"])
        XCTAssertEqual(viewModel.claimedSessionID, 777)
    }

    func testScanResultBlockedByRecapSetsGate() async {
        let stub = StubCaseSomeoneService()
        stub.pairClaimResult = .failure(CaseGateError.blockedByRecap(42))
        let viewModel = makeViewModel(service: stub)

        await viewModel.scanResult("ABC123")

        XCTAssertEqual(viewModel.gatedRecapSessionID, 42)
        XCTAssertNil(viewModel.claimedSessionID)
    }

    func testScanResultOtherErrorSetsMessage() async {
        let stub = StubCaseSomeoneService()
        stub.pairClaimResult = .failure(APIError.server(500))
        let viewModel = makeViewModel(service: stub)

        await viewModel.scanResult("ABC123")

        XCTAssertNil(viewModel.claimedSessionID)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testScanResultUnparseableCodeSetsMessageWithoutClaiming() async {
        let stub = StubCaseSomeoneService()
        let viewModel = makeViewModel(service: stub)

        await viewModel.scanResult("   ")

        XCTAssertTrue(stub.recordedShortCodes.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Prefill context

    func testPrefillContextIsExposed() {
        let viewModel = makeViewModel(
            service: StubCaseSomeoneService(),
            prefillCaseId: 6, prefillCaseTitle: "Ski resort: revenue up, profit down"
        )
        XCTAssertEqual(viewModel.prefillCaseId, 6)
        XCTAssertEqual(viewModel.prefillCaseTitle, "Ski resort: revenue up, profit down")
    }
}
