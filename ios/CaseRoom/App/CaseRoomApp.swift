/*
 * Purpose: App entry point; launches RootShell (the 5-slot floating-glass tab
 *          shell) and wires the UIKit app delegate needed for APNs device-token
 *          registration.
 * Inputs: none (DEBUG launch-arg hatches: -DSGallery, -AvatarSheet, -F2Timeline,
 *         -F2TimelinePromptNoOffer, -F2Home, -F2HomeTablet, -DevLogin,
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
            } else if ProcessInfo.processInfo.arguments.contains("-F2Timeline") {
                // Timeline-detail (canvas 7b) fixture hatch: initial prompt state.
                NavigationStack {
                    TimelineDetailView(viewModel: .init(fixtureDetail: PreviewTimelineFixture.detail,
                                                          fixtureCatalog: PreviewTimelineFixture.catalog))
                }
            } else if ProcessInfo.processInfo.arguments.contains("-F2TimelinePromptNoOffer") {
                // Same fixture, prompt pre-set to the no_offer result card.
                NavigationStack {
                    TimelineDetailView(viewModel: .init(fixtureDetail: PreviewTimelineFixture.detail,
                                                          fixtureCatalog: PreviewTimelineFixture.catalog,
                                                          promptStage: .result(PreviewTimelineFixture.noOfferResult)))
                }
            } else if ProcessInfo.processInfo.arguments.contains("-F2Home") {
                // Home (canvas 3a) fixture hatch: the July-16 persona, fixture-backed.
                NavigationStack {
                    HomeView(viewModel: .init(
                        fixtureDashboard: PreviewHomeFixture.dashboard, fixtureGauntlet: PreviewHomeFixture.gauntlet,
                        fixtureBoard: PreviewHomeFixture.board, fixtureProfile: PreviewHomeFixture.profile,
                        fixtureTimeline: PreviewHomeFixture.timelineDetail))
                }
            } else if ProcessInfo.processInfo.arguments.contains("-F2HomeTablet") {
                // Tablet Home (canvas 2a) fixture hatch: the July-17 persona.
                F2HomeTabletHatch()
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
    //  -DevLogin        authenticate against the running dev server (seeded user)
    //  -startTab <tab>  home|library|caseTab|community|drills
    //  -avatarOpen      present the avatar sheet in shell context
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
        if args.contains("-avatarOpen") {
            AppRouter.shared.avatarSheet = true
        }
    }
    #endif

    private static var apiHost: String {
        APIClient.shared.baseURL.host ?? "127.0.0.1"
    }
}

#if DEBUG
/// Standalone scaffold for the `-F2HomeTablet` shot: replicates RootShell's
/// `.regular` Home header (wordmark | date+greeting | avatar) above the
/// two-column tablet HomeView, so the shot is a faithful canvas-2a frame
/// without booting the full authenticated shell. Release-inert.
private struct F2HomeTabletHatch: View {
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            DSBackground()
            HomeView(viewModel: .init(
                fixtureDashboard: PreviewHomeTabletFixture.dashboard,
                fixtureGauntlet: PreviewHomeTabletFixture.gauntlet,
                fixtureBoard: PreviewHomeTabletFixture.board,
                fixtureProfile: PreviewHomeTabletFixture.profile,
                fixtureTimeline: PreviewHomeTabletFixture.timelineDetail,
                fixtureRecentSessions: PreviewHomeTabletFixture.recentSessions))
                .contentMargins(.top, 64, for: .scrollContent)
            header
        }
    }

    private var header: some View {
        HStack {
            WordmarkChip()
            Spacer()
            VStack(spacing: 2) {
                Text(HomeViewModel.dateKicker(for: Date())).dsText(.kicker).foregroundStyle(palette.muted)
                Text(HomeViewModel.greeting(
                    hour: Calendar.current.component(.hour, from: Date()),
                    displayName: PreviewHomeTabletFixture.profile.displayName)
                ).dsText(.h1TabSmall).foregroundStyle(palette.ink)
            }
            Spacer()
            AvatarPill(initials: "AO")
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }
}

/// The July-17 tablet persona (Decisions §7, canvas 2a pixel truth): streak 13,
/// 6 gauntlet slots (canvas literal copy "Three drills, seven minutes." is
/// persona-only — the live hero formula computes from slots.count, same
/// documented-estimate deviation as the phone fixture), cohort C-14 6th of 10
/// (335 pts, 4 behind №5's 339), diagnostic Structure 8.2/Communication 7.5/
/// Quant 6.6/Market sizing 5.3 FOCUS across 15 cases, rec "EV charging — size
/// the German market" (Market sizing · D3), next session T. Becker "Dental
/// roll-up M&A" today 18:00 candidate, LAST NIGHT 7.2 avg vs M. Lindqvist,
/// firms McKinsey 57d ON PACE / BCG 75d PUSH QUANT / Bain 83d EARLY.
private enum PreviewHomeTabletFixture {
    static let profile = ProfileDetail(
        id: 1, email: "amara.osei@wharton.upenn.edu", displayName: "Amara Osei",
        bio: "MBA '27", linkedinUrl: "https://linkedin.com/in/amara-osei",
        school: SchoolRef(id: 1, name: "Wharton", domain: "wharton.upenn.edu"), photoUrl: nil)

    static let gauntlet = Gauntlet(
        date: "2026-07-17", setKey: "set-2026-07-17", provisional: false,
        slots: (1...6).map { GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil) },
        streak: 13, submitted: false, result: nil)

    static let board = GroupBoard(
        scope: "group", group: GroupRef(id: 14, name: "C-14"),
        entries: [
            BoardEntry(userId: 10, displayName: "R. Vance", photoKey: nil, points: 400, rank: 1, streak: 20),
            BoardEntry(userId: 11, displayName: "P. Nair", photoKey: nil, points: 380, rank: 2, streak: 18),
            BoardEntry(userId: 12, displayName: "K. Chen", photoKey: nil, points: 360, rank: 3, streak: 15),
            BoardEntry(userId: 13, displayName: "S. Park", photoKey: nil, points: 350, rank: 4, streak: 14),
            BoardEntry(userId: 14, displayName: "T. Becker", photoKey: nil, points: 339, rank: 5, streak: 13),
            BoardEntry(userId: 1, displayName: "Amara Osei", photoKey: nil, points: 335, rank: 6, streak: 13),
            BoardEntry(userId: 15, displayName: "J. Silva", photoKey: nil, points: 320, rank: 7, streak: 11),
            BoardEntry(userId: 16, displayName: "M. Lindqvist", photoKey: nil, points: 310, rank: 8, streak: 9),
            BoardEntry(userId: 17, displayName: "A. Kim", photoKey: nil, points: 300, rank: 9, streak: 7),
            BoardEntry(userId: 18, displayName: "D. Ortiz", photoKey: nil, points: 290, rank: 10, streak: 5),
        ])

    static let dashboard = DashboardStats(
        sessionsFinalized: 10, streakWeeks: 3,
        nextSession: SessionSummary(
            id: 55, role: "candidate", otherUser: "T. Becker",
            caseTitle: "Dental roll-up M&A",
            scheduledAt: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()),
            state: nil, endedAt: nil, grade: nil),
        streakDays: 13, drillDoneToday: false,
        dimensionAverages: nil,
        recommendations: [
            Recommendation(caseId: 301, title: "EV charging — size the German market",
                            caseType: "Market sizing", difficulty: "D3", why: nil, rule: nil),
        ],
        diagnostic: DiagnosticStats(
            casesDone60D: 15,
            dimensions: [
                DimensionScore(dimension: "structure", avgScore: 8.2, samples: 15),
                DimensionScore(dimension: "communication", avgScore: 7.5, samples: 15),
                DimensionScore(dimension: "quant", avgScore: 6.6, samples: 15),
                DimensionScore(dimension: "market_sizing", avgScore: 5.3, samples: 15),
            ],
            strengths: [], weaknesses: [], focusDimension: "market_sizing",
            trend: DiagnosticTrend(recentAvg: nil, previousAvg: nil, delta: nil, direction: nil)),
        timeline: nil)

    static let timelineDetail = TimelineDetail(
        asOf: "2026-07-17",
        readiness: TimelineReadiness(label: "needs_work", ready: false, focusDimension: "Market sizing",
                                      recentCaseCount: 6, threshold: 6.0, minCases: 3),
        firms: [
            TimelineFirmDetail(
                firmId: 1, name: "McKinsey", slug: "mckinsey", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-12", region: "Americas",
                                        isEstimate: false, daysRemaining: 57, passed: false),
                readinessTag: "on_track", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 2, name: "BCG", slug: "bcg", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-30", region: "Americas",
                                        isEstimate: false, daysRemaining: 75, passed: false),
                readinessTag: "focus", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 3, name: "Bain", slug: "bain", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-10-08", region: "Americas",
                                        isEstimate: true, daysRemaining: 83, passed: false),
                readinessTag: "early", prompt: FirmPrompt(show: false)),
        ])

    static let recentSessions: [SessionSummary] = [
        SessionSummary(
            id: 40, role: "interviewer", otherUser: "M. Lindqvist",
            caseTitle: "Low-cost carrier enters the Nordic market",
            scheduledAt: nil, state: "completed",
            endedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            grade: 7.2),
    ]
}

/// DEBUG-only fake backing the `-AvatarSheet` screenshot hatch: the canvas 7a
/// persona (Amara Osei / Wharton → VERIFIED / a LinkedIn URL → LINKED /
/// notifications all-on) so the standalone shot shows the populated sheet.
private struct PreviewProfileService: ProfileService {
    func profile() async throws -> ProfileDetail {
        ProfileDetail(id: 1, email: "amara.osei@wharton.upenn.edu",
                      displayName: "Amara Osei", bio: "MBA '27",
                      linkedinUrl: "https://linkedin.com/in/amara-osei",
                      school: SchoolRef(id: 1, name: "Wharton", domain: "wharton.upenn.edu"), photoUrl: nil)
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
