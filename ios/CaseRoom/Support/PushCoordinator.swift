/*
 * Purpose: Requests push authorization, triggers APNs registration, and
 *          maps notification taps to an in-app route.
 * Inputs: UNUserNotificationCenter delegate callbacks; push payload `data`
 *         keys from the backend (`kind`, `proposal_id`/`session_id`/`user_id`).
 * Outputs: sets `pendingRoute` for RootShell to consume; device-token
 *          registration itself happens in CaseRoomApp's AppDelegate.
 * Run: one instance created by CaseRoomApp's AppDelegate, shared via
 *      SwiftUI environment; authorize+register triggered post-login.
 */

import Observation
import UIKit
import UserNotifications

enum PushRoute: Equatable {
    case proposals
    case session(Int)
    case proposeTo(Int)
}

@Observable
@MainActor
final class PushCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var pendingRoute: PushRoute?

    private var hasRequestedAuthorization = false

    /// Pure parser: maps a push payload's userInfo dict to an in-app route.
    /// `session_id` can arrive as either an Int or a String depending on how
    /// APNs re-serializes the JSON number, so both are accepted.
    nonisolated static func route(from userInfo: [AnyHashable: Any]) -> PushRoute? {
        guard let kind = userInfo["kind"] as? String else { return nil }

        switch kind {
        case "proposal":
            return .proposals
        case "accepted", "knock", "feedback", "starting_soon":
            guard let sessionID = intValue(userInfo["session_id"]) else { return nil }
            return .session(sessionID)
        case "free_now":
            // Instant-match: the toggler's `user_id` (Int or String, same as
            // session_id) is who to propose a session to.
            guard let userID = intValue(userInfo["user_id"]) else { return nil }
            return .proposeTo(userID)
        default:
            return nil
        }
    }

    private nonisolated static func intValue(_ raw: Any?) -> Int? {
        if let intValue = raw as? Int { return intValue }
        if let stringValue = raw as? String { return Int(stringValue) }
        return nil
    }

    /// Requests full (non-provisional) authorization and, if granted, kicks
    /// off remote-notification registration. D2: full auth after first login
    /// — the real-time matching value prop (knocks, starting-soon) justifies
    /// the prompt in-context; provisional would deliver those silently.
    func requestAuthorizationAndRegister() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // Best-effort — user can enable notifications later in Settings.
        }
    }

    /// Clears the process-lifetime authorization guard so the next
    /// `requestAuthorizationAndRegister()` call re-runs registration. Called
    /// on logout so a subsequent login by a different user re-registers the
    /// device token (backend upserts device_tokens keyed on token, reassigning
    /// user_id) instead of leaving the token pointed at the previous user.
    func resetRegistration() {
        hasRequestedAuthorization = false
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        pendingRoute = Self.route(from: response.notification.request.content.userInfo)
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
