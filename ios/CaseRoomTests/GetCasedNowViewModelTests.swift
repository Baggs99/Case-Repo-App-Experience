/*
 * Purpose: Unit tests for GetCasedNowViewModel — a stubbed GetCasedService and
 *          an injected clipboard writer prove load() populates the code/board,
 *          the pinned pairURL, ping()'s now-invite + toast, copyLink()'s
 *          pasteboard write + toast, and the minutes-free computation — all
 *          without a real network call or the system pasteboard.
 * Inputs: none (in-memory stub service + captured clipboard).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubGetCasedService: GetCasedService {
    var pairToken = PairToken(token: "tok", expiresAt: Date(timeIntervalSince1970: 1_000), shortCode: "K7Q-4TN")
    var availabilityResult = AvailabilityStatus(freeUntil: nil, others: [])
    var pairCreateError: Error?
    var availabilityError: Error?
    var nowInviteError: Error?

    private(set) var recordedPairCreateCaseIds: [Int?] = []
    private(set) var recordedNowInviteUserIds: [Int] = []

    func pairCreate(caseId: Int?) async throws -> PairToken {
        recordedPairCreateCaseIds.append(caseId)
        if let pairCreateError { throw pairCreateError }
        return pairToken
    }

    func availability() async throws -> AvailabilityStatus {
        if let availabilityError { throw availabilityError }
        return availabilityResult
    }

    func createNowInvite(toUserId: Int) async throws {
        recordedNowInviteUserIds.append(toUserId)
        if let nowInviteError { throw nowInviteError }
    }
}

@MainActor
final class GetCasedNowViewModelTests: XCTestCase {
    private func makeViewModel(
        service: StubGetCasedService,
        prefillCaseId: Int? = nil,
        now: @escaping () -> Date = { Date() },
        schools: [Int: String] = [:],
        clipboard: @escaping (String) -> Void = { _ in }
    ) -> GetCasedNowViewModel {
        GetCasedNowViewModel(
            prefillCaseId: prefillCaseId, service: service,
            now: now, schools: schools, writeClipboard: clipboard
        )
    }

    // MARK: - load()

    func testLoadPopulatesShortCodeExpiryAndBoard() async {
        let stub = StubGetCasedService()
        stub.pairToken = PairToken(token: "t", expiresAt: Date(timeIntervalSince1970: 2_000), shortCode: "K7Q-4TN")
        stub.availabilityResult = AvailabilityStatus(freeUntil: nil, others: [
            FreeUser(userId: 501, name: "S. Park", freeUntil: Date().addingTimeInterval(45 * 60)),
            FreeUser(userId: 502, name: "J. Okafor", freeUntil: Date().addingTimeInterval(20 * 60)),
        ])
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.shortCode, "K7Q-4TN")
        XCTAssertEqual(viewModel.expiresAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(viewModel.others.map(\.userId), [501, 502])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCaseLessPassesNilCaseId() async {
        let stub = StubGetCasedService()
        let viewModel = makeViewModel(service: stub, prefillCaseId: nil)

        await viewModel.load()

        XCTAssertEqual(stub.recordedPairCreateCaseIds, [nil])   // one call, caseId == nil
    }

    func testLoadPrefilledPassesCaseId() async {
        let stub = StubGetCasedService()
        let viewModel = makeViewModel(service: stub, prefillCaseId: 42)

        await viewModel.load()

        XCTAssertEqual(stub.recordedPairCreateCaseIds, [42])
    }

    func testLoadFailureSetsErrorMessage() async {
        let stub = StubGetCasedService()
        stub.pairCreateError = APIError.server(500)
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.shortCode.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - pairURL (PINNED payload)

    func testPairURLIsTheExactPinnedPayload() async {
        let stub = StubGetCasedService()
        stub.pairToken = PairToken(token: "t", expiresAt: Date(), shortCode: "K7Q-4TN")
        let viewModel = makeViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.pairURL, "caseroom://pair?code=K7Q-4TN")
    }

    // MARK: - Board rows (school + minutes)

    func testLiveNowMapsSchoolsAndMinutes() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let stub = StubGetCasedService()
        stub.availabilityResult = AvailabilityStatus(freeUntil: nil, others: [
            FreeUser(userId: 501, name: "S. Park", freeUntil: now.addingTimeInterval(45 * 60)),
            FreeUser(userId: 502, name: "J. Okafor", freeUntil: now.addingTimeInterval(20 * 60)),
        ])
        let viewModel = makeViewModel(service: stub, now: { now }, schools: [501: "Wharton", 502: "INSEAD"])

        await viewModel.load()

        XCTAssertEqual(viewModel.liveNow, [
            .init(id: 501, name: "S. Park", school: "Wharton", minutesFree: 45),
            .init(id: 502, name: "J. Okafor", school: "INSEAD", minutesFree: 20),
        ])
    }

    func testLiveNowOmitsSchoolWhenAbsent() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let stub = StubGetCasedService()
        stub.availabilityResult = AvailabilityStatus(freeUntil: nil, others: [
            FreeUser(userId: 777, name: "A. Osei", freeUntil: now.addingTimeInterval(30 * 60)),
        ])
        let viewModel = makeViewModel(service: stub, now: { now })   // no schools map

        await viewModel.load()

        XCTAssertEqual(viewModel.liveNow.first?.school, nil)
        XCTAssertEqual(viewModel.liveNow.first?.minutesFree, 30)
    }

    func testMinutesFreeRoundsAndClampsAtZero() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(GetCasedNowViewModel.minutesFree(until: now.addingTimeInterval(45 * 60), from: now), 45)
        XCTAssertEqual(GetCasedNowViewModel.minutesFree(until: now.addingTimeInterval(20 * 60), from: now), 20)
        XCTAssertEqual(GetCasedNowViewModel.minutesFree(until: now.addingTimeInterval(89), from: now), 1)   // 1.48 → 1
        XCTAssertEqual(GetCasedNowViewModel.minutesFree(until: now.addingTimeInterval(-60), from: now), 0)  // clamp
    }

    // MARK: - ping()

    func testPingSendsNowInviteAndToasts() async {
        let stub = StubGetCasedService()
        let viewModel = makeViewModel(service: stub)

        await viewModel.ping(userId: 501)

        XCTAssertEqual(stub.recordedNowInviteUserIds, [501])
        XCTAssertEqual(viewModel.toastMessage, "expires in 2 h")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testPingFailureSetsErrorMessage() async {
        let stub = StubGetCasedService()
        stub.nowInviteError = APIError.server(500)
        let viewModel = makeViewModel(service: stub)

        await viewModel.ping(userId: 501)

        XCTAssertNil(viewModel.toastMessage)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - copyLink()

    func testCopyLinkWritesPairURLToClipboardAndToasts() async {
        let stub = StubGetCasedService()
        stub.pairToken = PairToken(token: "t", expiresAt: Date(), shortCode: "K7Q-4TN")
        var written: String?
        let viewModel = makeViewModel(service: stub, clipboard: { written = $0 })

        await viewModel.load()
        viewModel.copyLink()

        XCTAssertEqual(written, "caseroom://pair?code=K7Q-4TN")
        XCTAssertEqual(viewModel.toastMessage, "Link copied")
    }
}
