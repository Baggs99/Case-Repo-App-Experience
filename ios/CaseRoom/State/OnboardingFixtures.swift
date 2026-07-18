/*
 * Purpose: DEBUG-only fixtures for the F9 onboarding flow — a StubOnboardingBackend
 *          (OnboardingService + ProfileService + OAuthStarter) with injectable
 *          outcomes (success by default; flags force verify-401, join-404,
 *          oauth-unavailable, request-failure, profile-failure) plus the Amara
 *          Osei / yale.edu persona seeds and a factory that parks a fixture-backed
 *          OnboardingViewModel at any Step for the screen hatches (Tasks 3-7).
 * Inputs: none.
 * Outputs: StubOnboardingBackend, OnboardingFixtures (seeds + viewModel(step:)).
 * Run: OnboardingRootView's -Onboarding <step> hatch builds via OnboardingFixtures.
 */

#if DEBUG
import Foundation

/// A single stub covering all three onboarding service protocols, so one
/// instance backs the whole VM. Flags default to the success path; set one to
/// force the matching failure. Reused by OnboardingViewModelTests via
/// @testable import (DEBUG symbols are visible to the test target).
final class StubOnboardingBackend: OnboardingService, ProfileService, OAuthStarter {
    var forceRequestFailure = false
    var forceVerify401 = false
    var forceJoin404 = false
    var forceOAuthUnavailable = false
    var forceProfileFailure = false
    var verifiedUser = User(id: 1, email: OnboardingFixtures.email, name: OnboardingFixtures.displayName)

    private(set) var requestOTPCalls = 0
    private(set) var startedProviders: [OAuthProvider] = []

    // MARK: OnboardingService

    func requestOTP(email: String) async throws {
        requestOTPCalls += 1
        if forceRequestFailure { throw APIError.transport(URLError(.notConnectedToInternet)) }
    }

    func verifyOTP(email: String, code: String) async throws -> User {
        if forceVerify401 { throw APIError.unauthorized }
        return verifiedUser
    }

    func joinGroup(inviteCode: String) async throws -> JoinedGroup {
        if forceJoin404 { throw OnboardingError.unknownInviteCode }
        return JoinedGroup(id: 14, name: "C-14", alreadyMember: false)
    }

    // MARK: OAuthStarter

    func start(provider: OAuthProvider) async throws {
        startedProviders.append(provider)
        if forceOAuthUnavailable { throw OnboardingError.oauthUnavailable }
    }

    // MARK: ProfileService (only updateProfile is exercised by onboarding)

    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail {
        if forceProfileFailure { throw APIError.transport(URLError(.notConnectedToInternet)) }
        return ProfileDetail(id: 1, email: OnboardingFixtures.email, displayName: displayName,
                             bio: bio, linkedinUrl: linkedinUrl, school: nil, photoUrl: nil)
    }

    func profile() async throws -> ProfileDetail { fatalError("onboarding never reads the profile") }
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String { fatalError("onboarding never uploads a photo") }
    func notificationSettings() async throws -> NotificationSettings { fatalError("onboarding never reads settings") }
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings { fatalError("onboarding never writes settings") }
}

enum OnboardingFixtures {
    // Amara Osei / yale.edu registry — the pinned persona continuity.
    static let email = "amara@yale.edu"
    static let displayName = "Amara Osei"
    static let inviteCode = "C14-XXXX"

    /// A fixture-backed VM parked at `step`, pre-seeded with the persona field
    /// values so a hatch renders a populated screen without a live server. Uses
    /// a throwaway SessionStore (finish()'s bootstrap is never driven in a shot).
    @MainActor
    static func viewModel(step: OnboardingViewModel.Step) -> OnboardingViewModel {
        let backend = StubOnboardingBackend()
        let vm = OnboardingViewModel(
            service: backend, oauthStarter: backend,
            profileService: backend, sessionStore: SessionStore()
        )
        vm.email = email
        vm.displayName = displayName
        vm.inviteCode = inviteCode
        vm.step = step
        return vm
    }
}
#endif
