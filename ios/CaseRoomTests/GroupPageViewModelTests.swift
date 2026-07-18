/*
 * Purpose: Unit tests for GroupPageViewModel — board ordering + the
 *          TOP FIVE ADVANCE split, the deterministic isAdmin match (my
 *          members[] row role == "admin"), the admin-only transfer/progress
 *          actions (right service call + reload, and the non-admin no-op
 *          guard), and the load() error path. Reuses StubCommunityService
 *          (CommunityViewModelTests.swift) rather than a second stub.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

private struct StubError: Error {}

@MainActor
final class GroupPageViewModelTests: XCTestCase {
    // MARK: - fixtures

    private static func member(_ id: Int, _ name: String, role: String) -> GroupMember {
        GroupMember(userId: id, displayName: name, photoUrl: nil, role: role)
    }

    private static func entry(_ id: Int, _ name: String, points: Int, rank: Int, streak: Int) -> GroupLeaderboardEntry {
        GroupLeaderboardEntry(userId: id, displayName: name, photoUrl: nil, points: points, rank: rank, streak: streak)
    }

    // Ten-member board, deliberately handed to the stub out of rank order —
    // load() must sort it, and the shape must exercise both sides of the
    // TOP FIVE ADVANCE divider.
    private static let tenMemberDetail = GroupDetail(
        group: GroupInfo(id: 14, name: "C-14", schoolId: 1, inviteCode: "C14-7QK2"),
        members: [
            member(10, "R. Vance", role: "admin"),
            member(1, "Amara Osei", role: "member"),
            member(11, "P. Nair", role: "member"),
        ],
        leaderboard: [
            entry(11, "P. Nair", points: 380, rank: 2, streak: 18),
            entry(10, "R. Vance", points: 400, rank: 1, streak: 20),
            entry(1, "Amara Osei", points: 331, rank: 6, streak: 12),
            entry(12, "K. Chen", points: 360, rank: 3, streak: 15),
            entry(13, "S. Park", points: 350, rank: 4, streak: 14),
            entry(14, "T. Becker", points: 339, rank: 5, streak: 13),
            entry(15, "J. Silva", points: 320, rank: 7, streak: 11),
            entry(16, "M. Lindqvist", points: 310, rank: 8, streak: 9),
            entry(17, "A. Kim", points: 300, rank: 9, streak: 7),
            entry(18, "D. Ortiz", points: 290, rank: 10, streak: 5),
        ])

    // MARK: - board ordering + TOP FIVE ADVANCE split

    func testLoadSortsLeaderboardByRank() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)

        XCTAssertEqual(vm.leaderboard.map(\.rank), Array(1...10))
        XCTAssertEqual(vm.leaderboard.first?.displayName, "R. Vance")
        XCTAssertEqual(vm.leaderboard.last?.displayName, "D. Ortiz")
    }

    // MARK: - reload() (Task 4: GroupPageContent's Retry action, which has no
    // groupId of its own to hand back — reload() reuses the last-loaded one.)

    func testReloadReusesTheLastLoadedGroupId() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)
        XCTAssertNotNil(vm.detail)

        stub.groupResult = .failure(StubError())
        await vm.reload()

        XCTAssertNil(vm.detail)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testReloadIsANoOpBeforeAnyLoad() async {
        let stub = StubCommunityService()
        let vm = GroupPageViewModel(service: stub, currentUserId: 10)

        await vm.reload()

        XCTAssertFalse(vm.hasLoaded)
    }

    func testTopFiveSplitPutsRanksOneThroughFiveAboveTheDivider() {
        let split = GroupPageViewModel.topFiveSplit(Self.tenMemberDetail.leaderboard)

        XCTAssertEqual(split.top.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(split.rest.map(\.rank), [6, 7, 8, 9, 10])
        // Amara — 6th of 10, 331 pts, day-12 streak (Decisions §3) — lands
        // just below the divider.
        XCTAssertEqual(split.rest.first?.displayName, "Amara Osei")
        XCTAssertEqual(split.rest.first?.points, 331)
        XCTAssertEqual(split.rest.first?.streak, 12)
    }

    func testTopFiveSplitWithFewerThanFiveEntriesLeavesRestEmpty() {
        let split = GroupPageViewModel.topFiveSplit(Array(Self.tenMemberDetail.leaderboard.prefix(3)))

        XCTAssertEqual(split.top.count, 3)
        XCTAssertTrue(split.rest.isEmpty)
    }

    func testInstancePropertiesMirrorTheStaticSplit() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)

        XCTAssertEqual(vm.topFive.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.restOfBoard.map(\.rank), [6, 7, 8, 9, 10])
    }

    // MARK: - isAdmin gating

    func testIsAdminTrueWhenCallersOwnMemberRowIsAdmin() {
        XCTAssertTrue(GroupPageViewModel.computeIsAdmin(members: Self.tenMemberDetail.members, currentUserId: 10))
    }

    func testIsAdminFalseWhenCallersOwnMemberRowIsPlainMember() {
        XCTAssertFalse(GroupPageViewModel.computeIsAdmin(members: Self.tenMemberDetail.members, currentUserId: 1))
    }

    func testIsAdminFalseWhenCurrentUserIdIsNil() {
        XCTAssertFalse(GroupPageViewModel.computeIsAdmin(members: Self.tenMemberDetail.members, currentUserId: nil))
    }

    func testIsAdminFalseWhenCallerIsNotAMember() {
        XCTAssertFalse(GroupPageViewModel.computeIsAdmin(members: Self.tenMemberDetail.members, currentUserId: 999))
    }

    func testLoadSetsIsAdminTrueForTheAdminUser() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)

        XCTAssertTrue(vm.isAdmin)
    }

    func testLoadSetsIsAdminFalseForAPlainMember() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 1)
        await vm.load(groupId: 14)

        XCTAssertFalse(vm.isAdmin)
    }

    // MARK: - transfer(toUserId:) — right service call, then reload

    func testTransferCallsServiceWithGroupIdAndTargetUserThenReloads() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)
        XCTAssertTrue(vm.isAdmin)

        // After the transfer, the server would hand admin to P. Nair (11) —
        // simulate that by swapping the stub's group() response so the
        // reload proves transfer() actually re-fetches.
        stub.groupResult = .success(GroupDetail(
            group: Self.tenMemberDetail.group,
            members: [
                Self.member(10, "R. Vance", role: "member"),
                Self.member(11, "P. Nair", role: "admin"),
            ],
            leaderboard: Self.tenMemberDetail.leaderboard))

        await vm.transfer(toUserId: 11)

        XCTAssertEqual(stub.transferCalls.count, 1)
        XCTAssertEqual(stub.transferCalls.first?.id, 14)
        XCTAssertEqual(stub.transferCalls.first?.userId, 11)
        // The reload picked up the new members[] — caller (10) is no longer admin.
        XCTAssertFalse(vm.isAdmin)
        XCTAssertNil(vm.errorMessage)
    }

    func testTransferFailureSurfacesErrorMessageWithoutCrashing() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)
        stub.transferResult = .failure(StubError())

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)
        await vm.transfer(toUserId: 11)

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - loadProgress(groupId:) — admin-only

    func testLoadProgressPopulatesForAnAdmin() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)
        stub.groupProgressResult = .success([
            GroupProgressMember(userId: 10, displayName: "R. Vance", casesDone: 22, meanGrade: 8.1, drillAttempts30D: 40, streak: 20),
            GroupProgressMember(userId: 18, displayName: "D. Ortiz", casesDone: 6, meanGrade: nil, drillAttempts30D: 12, streak: 5),
        ])

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)
        await vm.loadProgress(groupId: 14)

        XCTAssertEqual(vm.progress?.count, 2)
        XCTAssertEqual(vm.progress?.first?.casesDone, 22)
        XCTAssertNil(vm.progress?.last?.meanGrade)
    }

    func testLoadProgressIsANoOpForANonAdmin() async {
        let stub = StubCommunityService()
        stub.groupResult = .success(Self.tenMemberDetail)
        stub.groupProgressResult = .success([
            GroupProgressMember(userId: 10, displayName: "R. Vance", casesDone: 22, meanGrade: 8.1, drillAttempts30D: 40, streak: 20),
        ])

        let vm = GroupPageViewModel(service: stub, currentUserId: 1) // plain member
        await vm.load(groupId: 14)
        await vm.loadProgress(groupId: 14)

        XCTAssertNil(vm.progress)
    }

    // MARK: - load() error path

    func testLoadFailureClearsDetailAndSetsErrorMessage() async {
        let stub = StubCommunityService()
        stub.groupResult = .failure(StubError())

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        XCTAssertFalse(vm.hasLoaded)

        await vm.load(groupId: 14)

        XCTAssertTrue(vm.hasLoaded)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.detail)
        XCTAssertTrue(vm.leaderboard.isEmpty)
        XCTAssertFalse(vm.isAdmin)
    }

    func testRetryAfterFailureClearsErrorAndRepopulates() async {
        let stub = StubCommunityService()
        stub.groupResult = .failure(StubError())

        let vm = GroupPageViewModel(service: stub, currentUserId: 10)
        await vm.load(groupId: 14)
        XCTAssertNotNil(vm.errorMessage)

        stub.groupResult = .success(Self.tenMemberDetail)
        await vm.load(groupId: 14)

        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.detail)
        XCTAssertEqual(vm.leaderboard.count, 10)
    }
}
