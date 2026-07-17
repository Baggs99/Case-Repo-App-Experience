/*
 * Purpose: Root shell for CaseRoom — LoginView while logged out, four-tab
 *          navigation once authenticated. It routes every steering source
 *          through one AppRoute switch: notification taps (PushRoute), App
 *          Intents (AppRouter.shared.pending), and caseroom:// deep links.
 *          drill -> Today tab + drill sheet; freenow/proposeTo -> Today tab
 *          (the latter presents ProposeNowView); sessions -> Sessions tab.
 * Inputs: SessionStore (environment) bootstrap()s the persisted cookie on
 *         launch; PushCoordinator (environment) pendingRoute; AppRouter.shared.
 * Outputs: none.
 * Run: rendered by CaseRoomApp as the app's root view.
 */

import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(PushCoordinator.self) private var pushCoordinator
    @State private var appRouter = AppRouter.shared
    @State private var selectedTab: RootTab = .today
    @State private var presentedProposeTo: Int?
    // Bumped to ask the Today tab to open the drill sheet (a drill route).
    @State private var startDrillToken = 0

    enum RootTab: Hashable {
        case today, cases, sessions, profile
    }

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                TabView(selection: $selectedTab) {
                    TodayView(selectedTab: $selectedTab, startDrillToken: startDrillToken)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(RootTab.today)

                    CasesListView()
                        .tabItem { Label("Cases", systemImage: "folder") }
                        .tag(RootTab.cases)

                    SessionsView()
                        .tabItem { Label("Sessions", systemImage: "person.2.wave.2") }
                        .tag(RootTab.sessions)

                    ProfileView()
                        .tabItem { Label("You", systemImage: "person.crop.circle") }
                        .tag(RootTab.profile)
                }
                .tint(Color("BrandAccent"))
                .task {
                    await pushCoordinator.requestAuthorizationAndRegister()
                }
                .sheet(isPresented: Binding(
                    get: { presentedProposeTo != nil },
                    set: { if !$0 { presentedProposeTo = nil } }
                )) {
                    if let userId = presentedProposeTo {
                        ProposeNowView(toUser: userId)
                    }
                }
            } else {
                LoginView()
            }
        }
        .onChange(of: pushCoordinator.pendingRoute) { _, newRoute in
            guard let newRoute else { return }
            handle(DeepLink(newRoute))
            pushCoordinator.pendingRoute = nil
        }
        .onOpenURL { url in
            if let route = DeepLink.route(from: url) { handle(route) }
        }
        .task {
            await sessionStore.bootstrap()
        }
    }

    private func handle(_ route: DeepLink) {
        switch route {
        case .drill:
            selectedTab = .today
            startDrillToken += 1
        case .sessions:
            selectedTab = .sessions
        case .proposeTo(let userId):
            selectedTab = .today
            presentedProposeTo = userId
        case .freeNow:
            selectedTab = .today
        }
    }
}

#Preview {
    RootTabView()
        .environment(SessionStore())
        .environment(PushCoordinator())
}
