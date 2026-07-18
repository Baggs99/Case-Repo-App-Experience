/*
 * Purpose: Unit tests for PairViewModel — stubbed PairService proving the
 *          interviewer create+poll flow and the candidate claim flow,
 *          without a real network call or camera. The live QR scan itself
 *          (DataScannerViewController) is device-only and has no simulator
 *          camera to test against; it is exercised as a manual real-device
 *          check (see task-14-report.md), with claim(token:) unit-tested
 *          here by passing the token directly, as if it had been scanned.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubPairService: PairService {
    var pairCreateResult: Result<PairToken, Error> = .success(
        PairToken(token: "stub-token", expiresAt: Date().addingTimeInterval(600), shortCode: "STUB01")
    )
    var pairStatusResults: [Result<Int?, Error>] = [.success(nil)]
    var pairClaimResult: Result<Int, Error> = .success(42)

    private(set) var recordedCreateCaseIds: [Int] = []
    private(set) var recordedStatusTokens: [String] = []
    private(set) var recordedClaimTokens: [String] = []

    func pairCreate(caseId: Int) async throws -> PairToken {
        recordedCreateCaseIds.append(caseId)
        return try pairCreateResult.get()
    }

    func pairStatus(token: String) async throws -> Int? {
        recordedStatusTokens.append(token)
        // Once results are exhausted, keep repeating the last one so a
        // poll loop that outruns the fixture doesn't crash the test.
        let result = pairStatusResults.count > 1 ? pairStatusResults.removeFirst() : pairStatusResults[0]
        return try result.get()
    }

    func pairClaim(token: String) async throws -> Int {
        recordedClaimTokens.append(token)
        return try pairClaimResult.get()
    }
}

@MainActor
final class PairViewModelTests: XCTestCase {
    // MARK: - Interviewer: create

    func testCreateStoresTokenAndProducesAQRImage() async {
        let stub = StubPairService()
        stub.pairCreateResult = .success(PairToken(token: "abc123", expiresAt: Date().addingTimeInterval(600), shortCode: "ABC123"))
        stub.pairStatusResults = [.success(nil)]
        let viewModel = PairViewModel(service: stub, pollInterval: .milliseconds(1))

        await viewModel.create(caseId: 7)

        XCTAssertEqual(viewModel.token, "abc123")
        XCTAssertEqual(stub.recordedCreateCaseIds, [7])
        XCTAssertNotNil(viewModel.qrImage)
        viewModel.stopPolling()
    }

    func testCreateFailureSetsErrorMessage() async {
        let stub = StubPairService()
        stub.pairCreateResult = .failure(APIError.server(500))
        let viewModel = PairViewModel(service: stub, pollInterval: .milliseconds(1))

        await viewModel.create(caseId: 7)

        XCTAssertNil(viewModel.token)
        XCTAssertNil(viewModel.qrImage)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Interviewer: poll

    func testPollUntilReadyBecomesReadyOnlyAfterANonNilSessionId() async {
        let stub = StubPairService()
        stub.pairStatusResults = [.success(nil), .success(nil), .success(99)]
        let viewModel = PairViewModel(service: stub, pollInterval: .milliseconds(1))
        viewModel.token = "poll-token"

        await viewModel.pollUntilReady()

        XCTAssertEqual(viewModel.readySessionId, 99)
        XCTAssertEqual(stub.recordedStatusTokens, ["poll-token", "poll-token", "poll-token"])
    }

    // MARK: - Candidate: claim

    func testClaimStoresTheReturnedSessionId() async {
        let stub = StubPairService()
        stub.pairClaimResult = .success(123)
        let viewModel = PairViewModel(service: stub, pollInterval: .milliseconds(1))

        await viewModel.claim(token: "scanned-token")

        XCTAssertEqual(viewModel.claimedSessionId, 123)
        XCTAssertEqual(stub.recordedClaimTokens, ["scanned-token"])
    }

    func testClaimFailureSetsErrorMessage() async {
        let stub = StubPairService()
        stub.pairClaimResult = .failure(APIError.server(409))
        let viewModel = PairViewModel(service: stub, pollInterval: .milliseconds(1))

        await viewModel.claim(token: "scanned-token")

        XCTAssertNil(viewModel.claimedSessionId)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
