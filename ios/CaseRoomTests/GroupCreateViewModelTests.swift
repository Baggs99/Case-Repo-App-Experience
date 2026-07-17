/*
 * Purpose: Unit tests for GroupCreateViewModel — create() success populates
 *          `created` (invite_code + role:"admin" straight from the pinned
 *          POST /groups response), blank/whitespace names are rejected
 *          client-side with zero network calls, and a service error surfaces
 *          errorMessage while leaving `created` nil. Reuses StubCommunityService
 *          (CommunityViewModelTests.swift) rather than a second stub.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

private struct StubError: Error {}

@MainActor
final class GroupCreateViewModelTests: XCTestCase {
    // MARK: - create() success

    func testCreateSuccessSetsCreatedWithInviteCodeAndAdminRole() async {
        let stub = StubCommunityService()
        stub.createGroupResult = .success(GroupSummary(
            id: 20, name: "C-14 East", schoolId: 1, inviteCode: "C14E-9XJT", role: "admin"))

        let vm = GroupCreateViewModel(service: stub)
        vm.name = "C-14 East"
        await vm.create()

        XCTAssertEqual(stub.createGroupCalls, ["C-14 East"])
        XCTAssertEqual(vm.created?.name, "C-14 East")
        XCTAssertEqual(vm.created?.inviteCode, "C14E-9XJT")
        XCTAssertEqual(vm.created?.role, "admin")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isCreating)
    }

    func testCreateTrimsWhitespaceBeforeSendingTheName() async {
        let stub = StubCommunityService()
        stub.createGroupResult = .success(GroupSummary(
            id: 20, name: "C-14 East", schoolId: 1, inviteCode: "C14E-9XJT", role: "admin"))

        let vm = GroupCreateViewModel(service: stub)
        vm.name = "  C-14 East  "
        await vm.create()

        XCTAssertEqual(stub.createGroupCalls, ["C-14 East"])
    }

    // MARK: - client-side validation — no network call for blank/whitespace

    func testBlankNameIsRejectedWithoutANetworkCall() async {
        let stub = StubCommunityService()

        let vm = GroupCreateViewModel(service: stub)
        vm.name = ""
        await vm.create()

        XCTAssertTrue(stub.createGroupCalls.isEmpty)
        XCTAssertNil(vm.created)
        XCTAssertFalse(vm.isNameValid)
    }

    func testWhitespaceOnlyNameIsRejectedWithoutANetworkCall() async {
        let stub = StubCommunityService()

        let vm = GroupCreateViewModel(service: stub)
        vm.name = "   \n  "
        await vm.create()

        XCTAssertTrue(stub.createGroupCalls.isEmpty)
        XCTAssertNil(vm.created)
        XCTAssertFalse(vm.isNameValid)
    }

    func testNameOver100CharsIsRejectedWithoutANetworkCall() async {
        let stub = StubCommunityService()

        let vm = GroupCreateViewModel(service: stub)
        vm.name = String(repeating: "a", count: 101)
        await vm.create()

        XCTAssertTrue(stub.createGroupCalls.isEmpty)
        XCTAssertNil(vm.created)
        XCTAssertFalse(vm.isNameValid)
    }

    // MARK: - service error

    func testCreateFailureSetsErrorMessageAndLeavesCreatedNil() async {
        let stub = StubCommunityService()
        stub.createGroupResult = .failure(StubError())

        let vm = GroupCreateViewModel(service: stub)
        vm.name = "C-14 East"
        await vm.create()

        XCTAssertEqual(stub.createGroupCalls.count, 1)
        XCTAssertNil(vm.created)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isCreating)
    }

    func testRetryAfterFailureClearsErrorAndPopulatesCreated() async {
        let stub = StubCommunityService()
        stub.createGroupResult = .failure(StubError())

        let vm = GroupCreateViewModel(service: stub)
        vm.name = "C-14 East"
        await vm.create()
        XCTAssertNotNil(vm.errorMessage)

        stub.createGroupResult = .success(GroupSummary(
            id: 20, name: "C-14 East", schoolId: 1, inviteCode: "C14E-9XJT", role: "admin"))
        await vm.create()

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.created?.inviteCode, "C14E-9XJT")
    }
}
