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
    @State private var router = AppRouter.shared
    // The shell owns the drill sheet so the caseroom://drill widget + StartDrillIntent
    // open it reliably regardless of which tab (or a cold launch) is mounted.
    @State private var presentedDrill: DrillViewModel?

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
        .task { await sessionStore.bootstrap() }
    }

    private var authenticated: some View {
        ZStack(alignment: .bottom) {
            DSBackground()

            selectedTab
                .contentMargins(.bottom, 96, for: .scrollContent)
                .contentMargins(.top, 64, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DSTabBar(selection: $router.selection, maxWidth: hSize == .regular ? 560 : nil)
                .padding(.bottom, hSize == .regular ? 14 : 12)
        }
        .overlay(alignment: .top) {
            if hSize == .regular {
                HStack {
                    WordmarkChip()
                    Spacer()
                    Text(router.selection.label.capitalized).dsText(.h1Tab)
                    Spacer()
                    avatarButton
                }
                .padding(.horizontal, 28).padding(.top, 8)
            }
        }
        .overlay(alignment: .topLeading) {
            if hSize != .regular { WordmarkChip().padding(.leading, 16).padding(.top, 8) }
        }
        .overlay(alignment: .topTrailing) {
            if hSize != .regular { avatarButton.padding(.trailing, 16).padding(.top, 8) }
        }
        .task {
            #if DEBUG
            // The push-authorization OS alert can't be dismissed by simctl (no
            // tap); skip it on the -DevLogin screenshot path so the shell shot is
            // clean. Normal launches (and Release) always request as before.
            if ProcessInfo.processInfo.arguments.contains("-DevLogin") { return }
            #endif
            await pushCoordinator.requestAuthorizationAndRegister()
        }
        .sheet(isPresented: $router.avatarSheet) { AvatarSheetView() }
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
            // F5/F6 refit this into the dark takeover; the existing SessionView
            // is a real, working session screen for the interim.
            NavigationStack { SessionView(sessionId: target.id) }
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
    }

    // Mirrors the legacy TodayView.startDrill() wiring (FM/on-device engine path).
    private func makeDrill() -> DrillViewModel {
        DrillViewModel(
            engine: DrillEngineProvider.make(service: APIClient.shared, userId: sessionStore.user?.id ?? 0),
            recorder: AttemptRecorder(service: APIClient.shared)
        )
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
            CommunityTabStub()
        case .drills:
            DrillsTabStub()
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
