/*
 * Purpose: Unit tests for CommunityViewModel — a stubbed CommunityService
 *          proving the concurrent load() populates schoolStanding/groups/
 *          connections (incl. the null-school state) and that a failure
 *          surfaces errorMessage without crashing.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubCommunityService: CommunityService {
    var connectionsResult: Result<[Connection], Error> = .success([])
    var groupsResult: Result<[GroupSummary], Error> = .success([])
    var createGroupResult: Result<GroupSummary, Error>?
    var groupResult: Result<GroupDetail, Error>?
    var transferResult: Result<Void, Error> = .success(())
    var groupProgressResult: Result<[GroupProgressMember], Error>?
    var schoolStandingResult: Result<SchoolStanding, Error> = .success(SchoolStanding(school: nil, yourPercentile: nil))

    private(set) var transferCalls: [(id: Int, userId: Int)] = []
    private(set) var createGroupCalls: [String] = []

    func connections() async throws -> [Connection] { try connectionsResult.get() }
    func groups() async throws -> [GroupSummary] { try groupsResult.get() }

    func createGroup(name: String) async throws -> GroupSummary {
        createGroupCalls.append(name)
        guard let createGroupResult else { fatalError("not exercised by these tests") }
        return try createGroupResult.get()
    }

    func group(id: Int) async throws -> GroupDetail {
        guard let groupResult else { fatalError("not exercised by these tests") }
        return try groupResult.get()
    }

    func transferGroupAdmin(id: Int, userId: Int) async throws {
        transferCalls.append((id: id, userId: userId))
        try transferResult.get()
    }

    func groupProgress(id: Int) async throws -> [GroupProgressMember] {
        guard let groupProgressResult else { fatalError("not exercised by these tests") }
        return try groupProgressResult.get()
    }

    func schoolStanding() async throws -> SchoolStanding { try schoolStandingResult.get() }
}

private struct StubError: Error {}

@MainActor
final class CommunityViewModelTests: XCTestCase {
    // MARK: - load() populates from a fake service

    func testLoadPopulatesSchoolStandingGroupsAndConnections() async {
        let stub = StubCommunityService()
        stub.schoolStandingResult = .success(SchoolStanding(
            school: SchoolInfo(schoolId: 1, name: "Wharton", campusCity: "Philadelphia",
                                avgMemberPercentile: 69.8, rank: 2),
            yourPercentile: 91.0))
        stub.groupsResult = .success([
            GroupSummary(id: 14, name: "C-14", schoolId: 1, inviteCode: "C14-7QK2", role: "member"),
        ])
        stub.connectionsResult = .success([
            Connection(userId: 7, displayName: "S. Park", photoUrl: nil, bio: nil,
                       freeNow: true, swapInvitePending: false),
        ])

        let vm = CommunityViewModel(service: stub)
        XCTAssertFalse(vm.hasLoaded)

        await vm.load()

        XCTAssertTrue(vm.hasLoaded)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.schoolStanding?.school?.name, "Wharton")
        XCTAssertEqual(vm.schoolStanding?.school?.rank, 2)
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups[0].name, "C-14")
        XCTAssertEqual(vm.connections.count, 1)
        XCTAssertEqual(vm.connections[0].displayName, "S. Park")
        XCTAssertTrue(vm.connections[0].freeNow)
    }

    // MARK: - load() with a null school (dev-seed) still populates cleanly

    func testLoadWithNullSchoolLeavesSchoolNilNotAnError() async {
        let stub = StubCommunityService()
        stub.schoolStandingResult = .success(SchoolStanding(school: nil, yourPercentile: nil))

        let vm = CommunityViewModel(service: stub)
        await vm.load()

        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.schoolStanding?.school)
        XCTAssertTrue(vm.hasLoaded)
    }

    // MARK: - error path sets errorMessage

    func testLoadFailureSetsErrorMessage() async {
        let stub = StubCommunityService()
        stub.schoolStandingResult = .failure(StubError())

        let vm = CommunityViewModel(service: stub)
        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertNil(vm.schoolStanding)
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertTrue(vm.connections.isEmpty)
    }

    // MARK: - a retry after failure clears errorMessage on success

    func testRetryAfterFailureClearsError() async {
        let stub = StubCommunityService()
        stub.schoolStandingResult = .failure(StubError())

        let vm = CommunityViewModel(service: stub)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        stub.schoolStandingResult = .success(SchoolStanding(school: nil, yourPercentile: nil))
        await vm.load()

        XCTAssertNil(vm.errorMessage)
    }
}
