/*
 * Purpose: App entry point; launches RootShell (the 5-slot floating-glass tab
 *          shell) and wires the UIKit app delegate needed for APNs device-token
 *          registration.
 * Inputs: none (DEBUG launch-arg hatches: -DSGallery, -AvatarSheet, -F2Timeline,
 *         -F2TimelinePromptNoOffer, -F2Home, -F2HomeTablet, -F7Drills (+ optional
 *         -F7Board <c14|wharton|global|schools>), -F7Run <numeric|choice>,
 *         -F7Result, -DevLogin, -startTab <tab>, -avatarOpen, -LibraryFixtures,
 *         -CommunityFixtures, -GroupPageFixtures, -GroupCreateFixtures,
 *         -CaseFixtures (F3), -startTakeover [variant], -startRecap (F5),
 *         -OnbWelcome, -OnbEmail, -OnbPasscode (F9) — see the #if DEBUG blocks).
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
            } else if ProcessInfo.processInfo.arguments.contains("-F7Drills") {
                // Drills hub (canvas 5b) fixture hatch: the July-16 persona, submitted.
                // Optional `-F7Board <c14|wharton|global|schools>` (Task 3) presets
                // the active scope chip; all 4 scope fixtures are always injected so
                // simctl (which can't tap) can capture any of the 4 board shots
                // without a dev server.
                NavigationStack {
                    DrillsView(viewModel: .init(
                        fixtureGauntlet: PreviewDrillsFixture.gauntlet,
                        fixtureTrends: PreviewDrillsFixture.trends,
                        fixtureBoard: PreviewDrillsFixture.board,
                        boardScope: PreviewDrillsFixture.scope(for: Self.launchArgValue(after: "-F7Board")),
                        fixtureSchoolBoard: PreviewDrillsFixture.schoolBoard,
                        fixtureGlobalBoard: PreviewDrillsFixture.globalBoard,
                        fixtureSchoolsBoard: PreviewDrillsFixture.schoolsBoard))
                }
            } else if ProcessInfo.processInfo.arguments.contains("-F7Run") {
                // Gauntlet run frame (canvas 5b run) fixture hatch: `-F7Run
                // numeric` shows the keypad slot; `-F7Run choice` shows the 2×2
                // choice grid. Constant-clock, autoTick off → deterministic 00:00.
                GauntletRunView(viewModel: PreviewGauntletRunFixture.runVM(
                    mode: Self.launchArgValue(after: "-F7Run")))
            } else if ProcessInfo.processInfo.arguments.contains("-F7Result") {
                // Gauntlet result frame (canvas 5b result) fixture hatch:
                // percentile 66, +40 PTS, 5/6 correct, 3RD IN C-14, weak = market
                // sizing, elapsed 04:12.
                GauntletRunView(viewModel: PreviewGauntletRunFixture.resultVM)
            } else if ProcessInfo.processInfo.arguments.contains("-OnbWelcome") {
                // Onboarding welcome (F9-T3) fixture hatch: the mark-draws hero,
                // full-screen, VM parked at .welcome. onLogin is a no-op standalone
                // (the container wires it to LoginView in Task 7).
                OnboardingWelcomeView(viewModel: OnboardingFixtures.viewModel(step: .welcome))
            } else if ProcessInfo.processInfo.arguments.contains("-OnbEmail") {
                // Onboarding school-email gate (F9-T3) fixture hatch: STEP 1 OF 05,
                // fixture VM pre-seeded with amara@yale.edu so the field is populated
                // (simctl can't type).
                OnboardingEmailView(viewModel: OnboardingFixtures.viewModel(step: .email))
            } else if ProcessInfo.processInfo.arguments.contains("-OnbPasscode") {
                // Onboarding passcode (F9-T4) fixture hatch: STEP 2 OF 05, fixture
                // VM parked at .passcode (email amara@yale.edu shown in the body).
                // Seed a partial code ("123") DEBUG-locally so the shot proves the
                // 3-filled/3-empty dots state (simctl can't tap the keypad); the
                // shared fixture factory stays code-free for the tests.
                OnboardingPasscodeView(viewModel: {
                    let vm = OnboardingFixtures.viewModel(step: .passcode)
                    vm.code = "123"
                    return vm
                }())
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
    //  -CommunityFixtures  fake auth + selects the community tab; CommunityView
    //                    swaps in a fixture-backed CommunityViewModel — see
    //                    CommunityFixtures.swift.
    //  -GroupPageFixtures  fake auth + selects the community tab + pushes
    //                    .groupPage(14) onto communityPath; RootShell's
    //                    groupPageDestination(id:) swaps in a fixture-backed
    //                    GroupPageViewModel (admin variant) — see
    //                    CommunityFixtures.groupDetail/groupProgress.
    //  -GroupCreateFixtures  fake auth + presents the group-create sheet
    //                    already flipped true; RootShell's groupCreateSheet
    //                    swaps in a fixture-backed GroupCreateViewModel with
    //                    `created` pre-populated — see CommunityFixtures.
    //                    createdGroup — for the "YOU'RE THE ADMIN" shot.
    //  -startCaseDetail <id>  push .caseDetail(id) onto libraryPath (Task 4
    //                    screenshot hatch) — apply AFTER fake-auth so the
    //                    push lands on an already-authenticated shell.
    //  -CaseFixtures (F3)  fake auth + selects the Case tab; RootShell's
    //                    caseTabRoot swaps in a fixture-backed
    //                    CaseTabViewModel — see CaseFixtures.swift.
    //  -CaseSheet <name> (F3-T3, DEBUG)  under -CaseFixtures, CaseTabView opens
    //                    a verb-bar sheet on appear (getCased) so the OPEN sheet
    //                    can be screenshotted with no dev server. Release-inert.
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
        if args.contains("-CommunityFixtures") {
            // Fake auth, no network — CommunityView reads the same arg and
            // constructs a fixture-backed CommunityViewModel from
            // CommunityFixtures.swift, so the Community screenshot path needs
            // no dev server. Also selects the tab (unlike -LibraryFixtures,
            // which relies on a separate -startTab arg — F8-T1 pins this
            // hatch to select the tab on its own).
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.selection = .community
        }
        if args.contains("-CaseFixtures") {
            // MARK: F3 — fake auth, no network. RootShell's caseTabRoot reads
            // the same arg and swaps in a fixture-backed CaseTabViewModel
            // (CaseFixtures.swift), so the Case tab screenshot path needs no
            // dev server. Also selects the tab (mirrors -CommunityFixtures);
            // -startTab caseTab (already wired above) does the same thing.
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.selection = .caseTab
        }
        if args.contains("-GroupPageFixtures") {
            // Fake auth (same fixture user as -CommunityFixtures) + push
            // .groupPage(14) onto communityPath — RootShell's groupPageDestination
            // reads the same arg and builds a fixture-backed GroupPageViewModel
            // (admin variant) from CommunityFixtures.groupDetail/groupProgress,
            // so the group-page screenshot path needs no dev server either.
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.selection = .community
            AppRouter.shared.communityPath.append(.groupPage(14))
        }
        if args.contains("-GroupCreateFixtures") {
            // Fake auth (same fixture user as -CommunityFixtures) + present the
            // group-create sheet already flipped to `true` — RootShell's
            // groupCreateSheet reads the same arg and injects a fixture-backed
            // GroupCreateViewModel with `created` pre-populated
            // (CommunityFixtures.createdGroup), so the "YOU'RE THE ADMIN"
            // success-state screenshot needs no dev server and no typing/tapping.
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.groupCreate = true
        }
        if args.contains("-avatarOpen") {
            AppRouter.shared.avatarSheet = true
        }
        // MARK: - F5 — dark takeover screenshot hatch. Fake auth (no network) +
        // present the session fullScreenCover; RootShell.takeoverSession reads the
        // same arg and binds SessionView to SessionFixtures' stub service + no-op
        // signaling, so the dark `state:"lobby"` lobby captures with no dev server.
        if args.contains("-startTakeover") {
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.sessionTakeoverID = SessionFixtures.lobbySessionId
        }
        // MARK: - F5-T6 — recap report screenshot hatch. Fake auth (no network) +
        // present the LIGHT recap fullScreenCover; RootShell.recapReport reads the
        // same arg and binds RecapReportView to SessionFixtures.recapFlow, so the
        // canvas-6b recap (T. Becker, 4.1) captures with no dev server.
        if args.contains("-startRecap") {
            sessionStore.user = User(id: 1, email: "a@yale.edu", name: "Amara Osei")
            AppRouter.shared.recapSessionID = SessionFixtures.recapSessionId
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

    #if DEBUG
    /// The token immediately following a launch-arg flag, e.g. `-F7Board
    /// wharton` → `"wharton"`. nil when the flag is absent or has no value.
    private static func launchArgValue(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
    #endif
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
