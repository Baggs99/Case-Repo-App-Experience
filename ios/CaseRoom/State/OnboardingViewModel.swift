/*
 * Purpose: The F9 signup onboarding state machine — one @Observable @MainActor
 *          source of truth for the step, field values, submitting/error state,
 *          and the locally-held verified User. Drives welcome → email → passcode
 *          → account → group → done, holding the User locally so isAuthenticated
 *          flips ONLY in finish() (RootShell keeps showing the onboarding cover
 *          through the account/group steps rather than swapping to the shell).
 * Inputs: OnboardingService + OAuthStarter + ProfileService + SessionStore
 *         (injected; convenience init binds the live APIClient/WebAuth impls).
 * Outputs: none (network side effects via the injected services; the session
 *          cookie set by verifyOTP is the durable auth, cashed in by finish()).
 * Run: owned by OnboardingRootView (Task 7); fixtures via OnboardingFixtures.
 */

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    /// The six flow positions. Raw values double as the progress index so the
    /// mark's trim reads straight off `progressStep` (welcome is the pre-step
    /// intro → 0; email…done → 1…5, i.e. "STEP N OF 05").
    enum Step: Int {
        case welcome = 0, email, passcode, account, group, done
    }

    var step: Step = .welcome
    var email = ""
    var code = ""
    var displayName = ""
    var inviteCode = ""
    var isSubmitting = false
    var errorText: String?

    /// The verified user, held LOCALLY and never written to SessionStore.user —
    /// the whole retrofit invariant is that auth doesn't flip mid-flow (see
    /// finish()). Exposed read-only so a later step can greet the user by name.
    private(set) var user: User?

    /// STEP N OF 05: 1…5 for email…done, 0 for the welcome intro.
    var progressStep: Int {
        switch step {
        case .welcome: return 0
        case .email: return 1
        case .passcode: return 2
        case .account: return 3
        case .group: return 4
        case .done: return 5
        }
    }

    private let service: OnboardingService
    private let oauthStarter: OAuthStarter
    private let profileService: ProfileService
    let sessionStore: SessionStore

    private let genericError = "Something went wrong. Try again."

    // Live wiring: APIClient conforms to both OnboardingService and
    // ProfileService; SessionStore is threaded from the environment (it is NOT
    // a singleton), so the caller passes the app's shared instance.
    convenience init(sessionStore: SessionStore) {
        self.init(
            service: APIClient.shared,
            oauthStarter: WebAuthOAuthStarter(),
            profileService: APIClient.shared,
            sessionStore: sessionStore
        )
    }

    init(service: OnboardingService, oauthStarter: OAuthStarter, profileService: ProfileService, sessionStore: SessionStore) {
        self.service = service
        self.oauthStarter = oauthStarter
        self.profileService = profileService
        self.sessionStore = sessionStore
    }

    // MARK: - Navigation

    func goToEmail() {
        errorText = nil
        step = .email
    }

    func back() {
        errorText = nil
        switch step {
        case .email: step = .welcome
        case .passcode: step = .email
        case .account: step = .passcode
        case .group: step = .account
        case .welcome, .done: break
        }
    }

    // MARK: - Email gate

    func submitEmail() async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.requestOTP(email: email)
            step = .passcode
        } catch {
            // A dropped request must NOT advance — there'd be no code to enter.
            errorText = "Couldn't send the code. Try again."
        }
    }

    // MARK: - Passcode

    func submitCode() async {
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            user = try await service.verifyOTP(email: email, code: code)
            step = .account
        } catch APIError.unauthorized {
            code = ""
            errorText = "That code didn't match."
        } catch {
            errorText = genericError
        }
    }

    func resendCode() async {
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.requestOTP(email: email)
        } catch {
            errorText = "Couldn't send the code. Try again."
        }
    }

    // MARK: - Account completion

    func submitAccount() async {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await profileService.updateProfile(displayName: displayName, bio: nil, linkedinUrl: nil)
            step = .group
        } catch {
            errorText = genericError
        }
    }

    // OAuth completing account setup advances straight to the group step (the
    // web session cookie stands in for the display-name profile write). This is
    // a JUDGMENT call — flagged in the F9 report.
    func startOAuth(_ provider: OAuthProvider) async {
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await oauthStarter.start(provider: provider)
            step = .group
        } catch OnboardingError.oauthUnavailable {
            errorText = "Couldn't reach \(provider.displayName). Try email instead."
        } catch {
            errorText = genericError
        }
    }

    // MARK: - Group join

    func joinGroup() async {
        guard !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await service.joinGroup(inviteCode: inviteCode)
            step = .done
        } catch OnboardingError.unknownInviteCode {
            errorText = "We don't recognize that code."
        } catch {
            errorText = genericError
        }
    }

    func skipGroup() {
        errorText = nil
        step = .done
    }

    // MARK: - Finish

    // The ONLY place isAuthenticated may flip: the verify-step cookie is already
    // set, so bootstrap()'s /me succeeds and RootShell swaps to the shell.
    func finish() async {
        await sessionStore.finishOnboarding()
    }
}

private extension OAuthProvider {
    /// Human label for the "Couldn't reach <X>" copy — brand text only (the
    /// staircase-mark-only rule forbids brand glyphs).
    var displayName: String {
        switch self {
        case .google: return "Google"
        case .linkedin: return "LinkedIn"
        }
    }
}
