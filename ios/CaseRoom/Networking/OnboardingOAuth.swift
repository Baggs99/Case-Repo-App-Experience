/*
 * Purpose: OAuth entry seam for the F9 onboarding account step — opens the
 *          backend's /auth/<provider> browser route in an ASWebAuthenticationSession.
 * Inputs: OAuthProvider (google | linkedin); APIClient.shared.baseURL.
 * Outputs: none on success (the web session cookie is set browser-side);
 *          throws OnboardingError.oauthUnavailable on 503/cancel/error.
 * Run: OnboardingViewModel.startOAuth(provider:) calls OAuthStarter.start(provider:).
 *
 * LIVE-GAP (Thomas follow-up, plan §8.1): this CANNOT complete a live round-trip
 * today by construction. B5's OAuth callback 302s to `/` (https), which never
 * matches the native callbackURLScheme "caseroom", so the session's completion
 * handler never fires; separately the session runs in SafariViewService with its
 * own cookie jar, so even a successful web login's cookie never reaches
 * APIClient's HTTPCookieStorage. Live native OAuth needs a backend native-scheme
 * callback redirect + a token/cookie hand-back (and provisioned creds). Shipped
 * as a protocol-injected, mockable seam; proven by VM tests + fixtures, never a
 * live browser round-trip.
 */

import AuthenticationServices
import Foundation
import UIKit

enum OAuthProvider: String {
    case google
    case linkedin
}

protocol OAuthStarter {
    func start(provider: OAuthProvider) async throws
}

// The native callbackURLScheme ASWebAuthenticationSession watches for. The
// backend does not yet redirect to it (see LIVE-GAP above); kept here so the
// wiring is correct once the follow-up lands.
private let onboardingCallbackScheme = "caseroom"

final class WebAuthOAuthStarter: NSObject, OAuthStarter, ASWebAuthenticationPresentationContextProviding {
    // ASWebAuthenticationSession must be retained by the caller until auth
    // completes (Apple docs) — the transient main-queue start closure below is
    // not enough, so hold it here and clear it in the completion handler.
    private var activeSession: ASWebAuthenticationSession?

    func start(provider: OAuthProvider) async throws {
        let url = APIClient.shared.baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent(provider.rawValue)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: onboardingCallbackScheme
            ) { [weak self] callbackURL, error in
                self?.activeSession = nil
                // Any error (user cancel, 503, transport) or a missing callback
                // collapses to the single typed onboarding failure — the flow
                // only needs "OAuth didn't complete", not the specific cause.
                if error != nil || callbackURL == nil {
                    continuation.resume(throwing: OnboardingError.oauthUnavailable)
                } else {
                    continuation.resume()
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            // ASWebAuthenticationSession.start() must run on the main thread.
            DispatchQueue.main.async {
                if !session.start() {
                    self.activeSession = nil
                    continuation.resume(throwing: OnboardingError.oauthUnavailable)
                }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // The key window of the active foreground scene; a fresh anchor is a safe
        // fallback the system still presents from.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
