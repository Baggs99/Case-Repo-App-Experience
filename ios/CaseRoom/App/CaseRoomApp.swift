/*
 * Purpose: App entry point; launches RootShell (the 5-slot floating-glass tab
 *          shell) and wires the UIKit app delegate needed for APNs device-token
 *          registration.
 * Inputs: none (DEBUG launch-arg hatches: -DSGallery, -AvatarSheet, -DevLogin,
 *         -startTab <tab>, -avatarOpen — see the #if DEBUG blocks).
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
        RootShell()
            .environment(sessionStore)
            .environment(appDelegate.pushCoordinator)
            .onAppear {
                // Wire once at launch: the same shared PushCoordinator
                // instance RootShell observes, so logout resets its
                // registration guard and the next login's post-auth
                // .task re-registers the device token for the new user.
                let pushCoordinator = appDelegate.pushCoordinator
                sessionStore.onLogout = { @MainActor in
                    pushCoordinator.resetRegistration()
                }
            }
            #if DEBUG
            .task { await applyDebugLaunchHatches() }
            #endif
    }

    #if DEBUG
    // Screenshot-only launch hatches so simctl (which can't tap/type) can capture
    // the shell showing REAL re-homed content in a chosen state. Mirrors the
    // -DSGallery / -AvatarSheet pattern; inert on a normal launch.
    //  -DevLogin         authenticate against the running dev server (seeded user)
    //  -startTab <tab>   home|library|caseTab|community|drills
    //  -avatarOpen       present the avatar sheet in shell context
    //  -LibraryFixtures  fake auth (no network) + CasesListView/CaseDetailView
    //                    swap in the LibraryFixtures stub service — see
    //                    LibraryFixtures.swift.
    //  -startCaseDetail <id>  push .caseDetail(id) onto libraryPath (Task 4
    //                    screenshot hatch) — apply AFTER fake-auth so the
    //                    push lands on an already-authenticated shell.
    @MainActor
    private func applyDebugLaunchHatches() async {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-startTab"), idx + 1 < args.count {
            switch args[idx + 1] {
            case "home": AppRouter.shared.selection = .home
            case "library": AppRouter.shared.selection = .library
            case "caseTab": AppRouter.shared.selection = .caseTab
            case "community": AppRouter.shared.selection = .community
            case "drills": AppRouter.shared.selection = .drills
            default: break
            }
        }
        if args.contains("-DevLogin") {
            await sessionStore.login(email: "a@yale.edu", password: "caseroom-dev-1")
        }
        if args.contains("-LibraryFixtures") {
            // Fake auth, no network — CasesListView reads the same arg and
            // routes its LibraryViewModel to the FixtureLibraryService stub,
            // so the whole Library screenshot path needs no dev server.
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
        }
        if args.contains("-avatarOpen") {
            AppRouter.shared.avatarSheet = true
        }
        if let idx = args.firstIndex(of: "-startCaseDetail"), idx + 1 < args.count,
           let caseId = Int(args[idx + 1]) {
            // Runs after the -LibraryFixtures/-DevLogin auth above so the
            // detail push lands on an authenticated RootShell (not the login
            // screen); AppRouter.go(to:) also selects the Library tab.
            AppRouter.shared.go(to: .caseDetail(caseId))
        }
    }
    #endif

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
