/*
 * Purpose: Observable auth state gating the app between LoginView and tabs.
 * Inputs: APIClient.shared (cookie-session backed).
 * Outputs: none (in-memory state only; the session cookie is the durable
 *          store, held in the App Group's shared cookie store). Logout also
 *          clears the widget snapshot and the API-host group cookies.
 * Run: instantiated once by CaseRoomApp and passed down via environment.
 */

import Foundation
import Observation

@Observable
final class SessionStore {
    var user: User?
    var isAuthenticated: Bool { user != nil }
    var lastError: String?

    /// Injected hook invoked after logout clears `user`. Wired at app launch
    /// to reset PushCoordinator's registration guard, keeping SessionStore
    /// decoupled from push/notification concerns and unit-testable in
    /// isolation.
    var onLogout: (() async -> Void)?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func bootstrap() async {
        do {
            user = try await client.me()
        } catch APIError.unauthorized {
            user = nil
        } catch {
            user = nil
        }
    }

    func login(email: String, password: String) async {
        lastError = nil
        do {
            user = try await client.login(email: email, password: password)
        } catch APIError.unauthorized {
            lastError = "Invalid email or password."
        } catch {
            lastError = "Couldn't reach the server. Try again."
        }
    }

    func logout() async {
        do {
            try await client.logout()
        } catch {
            // Best-effort — clear local state regardless of server outcome.
        }
        user = nil
        // Clear App Group state so the widget process can't read the
        // logged-out user's snapshot or reuse the group session cookie.
        SnapshotStore.clear()
        AppGroup.clearCookies(for: client.baseURL.host ?? "127.0.0.1")
        await onLogout?()
    }
}
