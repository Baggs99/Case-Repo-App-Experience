/*
 * Purpose: App entry point; launches the root tab-based UI and wires the
 *          UIKit app delegate needed for APNs device-token registration.
 * Inputs: none.
 * Outputs: none.
 * Run: built as part of the CaseRoom.app target via Xcode/xcodebuild.
 */

import SwiftUI
import UIKit
import UserNotifications

@main
struct CaseRoomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()

    init() {
        // Before any network use: bring an older build's session cookie into
        // the App Group's shared store so an already-logged-in user stays
        // authenticated after upgrading (idempotent, group-container gated).
        AppGroup.migrateCookiesIfNeeded(apiHost: Self.apiHost)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(sessionStore)
                .environment(appDelegate.pushCoordinator)
                .onAppear {
                    // Wire once at launch: the same shared PushCoordinator
                    // instance RootTabView observes, so logout resets its
                    // registration guard and the next login's post-auth
                    // .task re-registers the device token for the new user.
                    let pushCoordinator = appDelegate.pushCoordinator
                    sessionStore.onLogout = { @MainActor in
                        pushCoordinator.resetRegistration()
                    }
                }
        }
    }

    private static var apiHost: String {
        APIClient.shared.baseURL.host ?? "127.0.0.1"
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let pushCoordinator = PushCoordinator()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = pushCoordinator
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await APIClient.shared.registerDevice(token: token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
}
