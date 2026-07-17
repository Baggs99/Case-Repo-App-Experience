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
        // Register the bundled design fonts before first use (UIAppFonts is the
        // primary path; this idempotent call is belt-and-suspenders).
        DSFonts.register()
        // Before any network use: bring an older build's session cookie into
        // the App Group's shared store so an already-logged-in user stays
        // authenticated after upgrading (idempotent, group-container gated).
        AppGroup.migrateCookiesIfNeeded(apiHost: Self.apiHost)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Debug hatch for F0 screenshot evidence. Does not alter normal
            // launch or navigation (F1 owns navigation).
            if ProcessInfo.processInfo.arguments.contains("-DSGallery") {
                DesignSystemGallery()
            } else if ProcessInfo.processInfo.arguments.contains("-AvatarSheet") {
                ZStack { DSBackground() }
                    .sheet(isPresented: .constant(true)) {
                        // Fake-backed VM so the standalone shot shows the
                        // populated canvas-7a persona (not a logged-out sheet).
                        AvatarSheetView(viewModel: AvatarSheetViewModel(service: PreviewProfileService()))
                            .environment(SessionStore())
                    }
            } else {
                rootView
            }
            #else
            rootView
            #endif
        }
    }

    private var rootView: some View {
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

    private static var apiHost: String {
        APIClient.shared.baseURL.host ?? "127.0.0.1"
    }
}

#if DEBUG
/// DEBUG-only fake backing the `-AvatarSheet` screenshot hatch: the canvas 7a
/// persona (Amara Osei / Wharton → VERIFIED / a LinkedIn URL → LINKED /
/// notifications all-on) so the standalone shot shows the populated sheet.
private struct PreviewProfileService: ProfileService {
    func profile() async throws -> ProfileDetail {
        ProfileDetail(id: 1, email: "amara.osei@wharton.upenn.edu",
                      displayName: "Amara Osei", bio: "MBA '27",
                      linkedinUrl: "https://linkedin.com/in/amara-osei",
                      school: "Wharton", photoUrl: nil)
    }
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail {
        try await profile()
    }
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String { "/avatars/1.png" }
    func notificationSettings() async throws -> NotificationSettings {
        NotificationSettings(proposals: true, sessionReminders: true, feedback: true, freeNow: true, community: true)
    }
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings { settings }
}
#endif

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
