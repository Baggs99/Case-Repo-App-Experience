/*
 * Purpose: Root shell — LoginView while logged out; once authenticated, the
 *          5-slot floating-glass tab shell (HOME · LIBRARY · ⬤CASE · COMMUNITY ·
 *          DRILLS) with F0 chrome installed. Routes every steering source
 *          (push taps, App Intents, caseroom:// deep links) through AppRouter
 *          onto the pinned AppRoute registry. No You tab — the top-trailing
 *          avatar pill opens the avatar sheet.
 * Inputs: SessionStore (bootstrap), PushCoordinator (pendingRoute), AppRouter.shared.
 * Outputs: none.
 * Run: rendered by CaseRoomApp as the app's root view.
 */

import SwiftUI

struct RootShell: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(PushCoordinator.self) private var pushCoordinator
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dsPalette) private var palette
    @State private var router = AppRouter.shared
    // The shell owns the drill sheet so the caseroom://drill widget + StartDrillIntent
    // open it reliably regardless of which tab (or a cold launch) is mounted.
    @State private var presentedDrill: DrillViewModel?
    // The shell also owns the gauntlet run cover (mirrors presentedDrill) so the
    // Home hero + Drills Begin both launch it identically, surviving tab switches.
    @State private var presentedGauntlet: GauntletRunViewModel?

    // F4 Task 3, minimal additive (F1 deferred tab-stack mounting to F4):
    // canvas 5a's pushed case detail shows only a plain `‹ Library` back +
    // tag, no top pills, no tab bar. True only while Library owns the tab AND
    // has a pushed route — every other tab (and the Library list itself) is
    // unaffected.
    private var libraryDetailOpen: Bool { router.selection == .library && !router.libraryPath.isEmpty }

    // F8 Task 2 parallel: the pushed group page (canvas 6a C-14 detail) ships
    // with its own `‹ Back` + slate context label chrome, same as Library's
    // pushed case detail — no top pills, no tab bar while it's on screen.
    private var communityDetailOpen: Bool { router.selection == .community && !router.communityPath.isEmpty }

    // Generalized gate for the three top-pill overlays + the tab bar: true
    // while ANY tab has a pushed detail route on screen.
    private var detailOpen: Bool { libraryDetailOpen || communityDetailOpen }

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                authenticated
            } else {
                LoginView()
            }
        }
        .onChange(of: pushCoordinator.pendingRoute) { _, newRoute in
            guard let newRoute else { return }
            router.handlePush(newRoute)
            pushCoordinator.pendingRoute = nil
        }
        .onChange(of: router.pending) { _, newRoute in
            guard let newRoute else { return }
            router.go(to: newRoute)
            router.pending = nil
        }
        .onOpenURL { url in
            if let link = DeepLink.route(from: url) { router.handleDeepLink(link) }
        }
        .task {
            #if DEBUG
            // -LibraryFixtures/-CommunityFixtures fake auth directly (CaseRoomApp.
            // applyDebugLaunchHatches) with no dev server running; bootstrap()'s
            // client.me() would hit a dead 127.0.0.1 host, fail unauthorized, and
            // race-clobber the fake user back to nil. Skip it on these
            // screenshot-only paths.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-LibraryFixtures") || args.contains("-CommunityFixtures")
                || args.contains("-GroupPageFixtures") || args.contains("-GroupCreateFixtures")
                || args.contains("-startTakeover") { return } // F5
            #endif
            await sessionStore.bootstrap()
        }
    }

    private var authenticated: some View {
        ZStack(alignment: .bottom) {
            DSBackground()

            selectedTab
                .contentMargins(.bottom, 96, for: .scrollContent)
                .contentMargins(.top, 64, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !detailOpen {
                DSTabBar(selection: $router.selection, maxWidth: hSize == .regular ? 560 : nil)
                    .padding(.bottom, hSize == .regular ? 14 : 12)
            }
        }
        .overlay(alignment: .top) {
            if hSize == .regular && !detailOpen {
                HStack {
                    WordmarkChip()
                    Spacer()
                    if router.selection == .home {
                        // Canvas 2a: date kicker stacked over the greeting,
                        // centered — replaces the plain "Home" tab label.
                        VStack(spacing: 2) {
                            Text(HomeViewModel.dateKicker(for: Date())).dsText(.kicker).foregroundStyle(palette.muted)
                            Text(HomeViewModel.greeting(
                                hour: Calendar.current.component(.hour, from: Date()),
                                displayName: sessionStore.user?.name)
                            ).dsText(.h1TabSmall).foregroundStyle(palette.ink)
                        }
                    } else {
                        Text(router.selection.label.capitalized).dsText(.h1Tab)
                    }
                    Spacer()
                    avatarButton
                }
                .padding(.horizontal, 28).padding(.top, 8)
            }
        }
        .overlay(alignment: .topLeading) {
            if hSize != .regular && !detailOpen { WordmarkChip().padding(.leading, 16).padding(.top, 8) }
        }
        .overlay(alignment: .topTrailing) {
            if hSize != .regular && !detailOpen { avatarButton.padding(.trailing, 16).padding(.top, 8) }
        }
        .task {
            #if DEBUG
            // The push-authorization OS alert can't be dismissed by simctl (no
            // tap); skip it on DEBUG screenshot paths so the shot is clean.
            // Normal launches (and Release) always request as before.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-DevLogin") || args.contains("-LibraryFixtures") || args.contains("-CommunityFixtures")
                || args.contains("-GroupPageFixtures") || args.contains("-GroupCreateFixtures")
                || args.contains("-startTakeover") { return } // F5
            #endif
            await pushCoordinator.requestAuthorizationAndRegister()
        }
        .sheet(isPresented: $router.avatarSheet) { AvatarSheetView() }
        .sheet(isPresented: $router.groupCreate) { groupCreateSheet }
        .sheet(item: Binding(
            get: { router.proposeToUserID.map(ProposeTarget.init) },
            set: { if $0 == nil { router.proposeToUserID = nil } }
        )) { target in
            ProposeNowView(toUser: target.id)
        }
        .fullScreenCover(item: Binding(
            get: { router.sessionTakeoverID.map(TakeoverTarget.init) },
            set: { if $0 == nil { router.sessionTakeoverID = nil } }
        )) { target in
            // MARK: - F5 — dark takeover seam. The single place the whole session
            // subtree (lobby → negotiation → live) is themed dark; every glass
            // panel/scrim/DSBackground under here re-reads \.dsPalette and goes
            // dark. T5's DebriefView re-overrides to .light at its own root, still
            // inside this cover, so the debrief returns to daylight.
            NavigationStack { takeoverSession(id: target.id) }
                .dsTheme(.dark)
        }
        // Drill run — presented at the (stable) authenticated shell view, not inside a
        // tab, so it survives tab switches and warm foregrounding. `initial: true` also
        // covers the terminated cold-launch case: caseroom://drill fires .onOpenURL and
        // sets drillRun=true BEFORE bootstrap() flips isAuthenticated (so this view isn't
        // mounted yet); evaluating on mount presents the already-true flag. onDismiss
        // clears the flag so it can't get stuck true (a plain Bool never re-fires true→true).
        .onChange(of: router.drillRun, initial: true) { _, on in
            if on, presentedDrill == nil { presentedDrill = makeDrill() }
        }
        .sheet(item: $presentedDrill, onDismiss: { router.drillRun = false }) { drill in
            DrillView(viewModel: drill)
        }
        // Gauntlet run — the immersive server-scored cover (deliberately a
        // fullScreenCover, not a sheet). FLAG wiring mirrors .drillRun above:
        // onChange(initial:true) covers cold launch, onDismiss clears the flag
        // (and the "See today's result" preview) so it can't stick true.
        .onChange(of: router.gauntletRun, initial: true) { _, on in
            if on, presentedGauntlet == nil { presentedGauntlet = makeGauntletRun() }
        }
        .fullScreenCover(item: $presentedGauntlet, onDismiss: {
            router.gauntletRun = false
            router.gauntletResult = nil
        }) { runViewModel in
            GauntletRunView(viewModel: runViewModel)
        }
    }

    // MARK: - F5 — takeover session builder. `-startTakeover` swaps in the
    // fixture-backed SessionService + no-op signaling (SessionFixtures.swift) so
    // simctl captures the dark `state:"lobby"` takeover with no dev server and no
    // live socket; the live path is the real SessionView (default services).
    @ViewBuilder
    private func takeoverSession(id: Int) -> some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-startTakeover") {
            // Optional variant token after -startTakeover: lobby (default, T2) |
            // nego | negoInterviewer | negoKept (F5-T3).
            let variant = idx + 1 < args.count ? args[idx + 1] : "lobby"
            switch variant {
            case "nego":
                SessionView(sessionId: id, service: SessionFixtures.negoCandidateService,
                            signaling: SessionFixtures.negoSignaling,
                            flowService: SessionFixtures.negoCandidateFlow)
            case "negoInterviewer":
                SessionView(sessionId: id, service: SessionFixtures.negoInterviewerService,
                            signaling: SessionFixtures.negoSignaling,
                            flowService: SessionFixtures.negoInterviewerFlow)
            case "negoKept":
                SessionFixtures.negoKeptStandalone()
            default:
                SessionView(sessionId: id, service: SessionFixtures.lobbyService,
                            signaling: SessionFixtures.lobbySignaling)
            }
        } else {
            SessionView(sessionId: id)
        }
        #else
        SessionView(sessionId: id)
        #endif
    }

    // Mirrors the legacy TodayView.startDrill() wiring (FM/on-device engine path).
    private func makeDrill() -> DrillViewModel {
        DrillViewModel(
            engine: DrillEngineProvider.make(service: APIClient.shared, userId: sessionStore.user?.id ?? 0),
            recorder: AttemptRecorder(service: APIClient.shared)
        )
    }

    // F8 Task 3: the group-create sheet. `-GroupCreateFixtures` injects a
    // fixture-backed VM with `created` pre-populated (CommunityFixtures.
    // createdGroup) so simctl gets the "YOU'RE THE ADMIN" success state with
    // no dev server and no typing/tapping — mirrors groupPageDestination(id:).
    @ViewBuilder
    private var groupCreateSheet: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GroupCreateFixtures") {
            GroupCreateView(viewModel: GroupCreateViewModel(fixtureCreated: CommunityFixtures.createdGroup))
        } else {
            GroupCreateView()
        }
        #else
        GroupCreateView()
        #endif
    }

    // F8 Task 2: the `.groupPage` destination. `-GroupPageFixtures` (mirrors
    // `-CommunityFixtures`) injects a fixture-backed VM (admin variant — see
    // CommunityFixtures.groupDetail/groupProgress) so simctl gets a populated
    // shot with no dev server; the live path passes sessionStore.user?.id
    // through as the isAdmin-match seam (same pattern as makeDrill() above).
    @ViewBuilder
    private func groupPageDestination(id: Int) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GroupPageFixtures") {
            GroupPageView(groupId: id, viewModel: GroupPageViewModel(
                fixtureDetail: CommunityFixtures.groupDetail,
                fixtureIsAdmin: true,
                fixtureProgress: CommunityFixtures.groupProgress))
        } else {
            GroupPageView(groupId: id, currentUserId: sessionStore.user?.id)
        }
        #else
        GroupPageView(groupId: id, currentUserId: sessionStore.user?.id)
        #endif
    }

    // The live server-gauntlet run VM. When router.gauntletResult is set (Drills
    // "See today's result"), it opens straight into the result phase — no re-run.
    private func makeGauntletRun() -> GauntletRunViewModel {
        GauntletRunViewModel(service: APIClient.shared, preloadedResult: router.gauntletResult)
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch router.selection {
        case .home:
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        if case .timelineDetail = route {
                            TimelineDetailView()
                        }
                    }
            }
        case .library:
            CasesListView()
        case .caseTab:
            SessionsView()
        case .community:
            NavigationStack(path: $router.communityPath) {
                CommunityView()
                    .navigationDestination(for: AppRoute.self) { route in
                        if case .groupPage(let id) = route {
                            groupPageDestination(id: id)
                        }
                    }
            }
        case .drills:
            DrillsView()
        }
    }

    private var avatarButton: some View {
        Button { router.avatarSheet = true } label: { AvatarPill(initials: initials) }
            .buttonStyle(.plain)
    }

    private var initials: String {
        let parts = (sessionStore.user?.name ?? "").split(separator: " ").compactMap(\.first)
        return String(parts.prefix(2)).uppercased()
    }
}

// Identifiable wrappers so `.sheet(item:)` / `.fullScreenCover(item:)` drive off Int.
private struct ProposeTarget: Identifiable { let id: Int }
private struct TakeoverTarget: Identifiable { let id: Int }

#Preview {
    RootShell()
        .environment(SessionStore())
        .environment(PushCoordinator())
}
