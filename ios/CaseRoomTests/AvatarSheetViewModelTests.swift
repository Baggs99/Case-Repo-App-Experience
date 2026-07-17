/*
 * Purpose: Unit tests for AvatarSheetViewModel — load, master notifications
 *          toggle semantics (all-five), verified/linked derivation, optimistic
 *          revert on failure.
 * Inputs: an injected fake ProfileService.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class AvatarSheetViewModelTests: XCTestCase {
    func testLoadPopulatesProfileAndSettings() async {
        let svc = FakeProfileService()
        let vm = AvatarSheetViewModel(service: svc)
        await vm.load()
        XCTAssertEqual(vm.profile?.displayName, "Amara Osei")
        XCTAssertTrue(vm.schoolVerified)
        XCTAssertTrue(vm.linkedAccountsLinked)
        XCTAssertTrue(vm.notificationsOn)  // fake defaults all-true
    }

    func testToggleOffWritesAllFalse() async {
        let svc = FakeProfileService()
        let vm = AvatarSheetViewModel(service: svc)
        await vm.load()
        await vm.setNotifications(false)
        XCTAssertFalse(vm.notificationsOn)
        XCTAssertEqual(svc.lastWritten?.allEnabled, false)
        XCTAssertEqual(svc.lastWritten?.proposals, false)
        XCTAssertEqual(svc.lastWritten?.community, false)
    }

    func testToggleRevertsOnFailure() async {
        let svc = FakeProfileService(); svc.failWrites = true
        let vm = AvatarSheetViewModel(service: svc)
        await vm.load()
        XCTAssertTrue(vm.notificationsOn)
        await vm.setNotifications(false)
        XCTAssertTrue(vm.notificationsOn) // reverted
        XCTAssertNotNil(vm.errorMessage)
    }

    func testSchoolNotVerifiedWhenEmpty() async {
        let svc = FakeProfileService(); svc.school = nil
        let vm = AvatarSheetViewModel(service: svc)
        await vm.load()
        XCTAssertFalse(vm.schoolVerified)
    }
}

private final class FakeProfileService: ProfileService, @unchecked Sendable {
    var school: String? = "Wharton"
    var failWrites = false
    var lastWritten: NotificationSettings?

    func profile() async throws -> ProfileDetail {
        ProfileDetail(id: 1, email: "a@yale.edu", displayName: "Amara Osei",
                      bio: "MBA '27", linkedinUrl: "https://linkedin.com/in/amara",
                      school: school, photoUrl: nil)
    }
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail {
        try await profile()
    }
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String { "/avatars/1.png" }
    func notificationSettings() async throws -> NotificationSettings {
        NotificationSettings(proposals: true, sessionReminders: true, feedback: true, freeNow: true, community: true)
    }
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings {
        if failWrites { throw APIError.server(500) }
        lastWritten = settings
        return settings
    }
}
