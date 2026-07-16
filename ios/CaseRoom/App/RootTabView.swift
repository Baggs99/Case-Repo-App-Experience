/*
 * Purpose: Root shell for CaseRoom — LoginView while logged out, four-tab
 *          navigation once authenticated. Also routes notification taps: a
 *          free_now (instant-match) push opens the Today tab and presents
 *          ProposeNowView; every other route selects the Sessions tab.
 * Inputs: SessionStore (environment), whose bootstrap() checks the
 *         persisted session cookie on launch; PushCoordinator (environment),
 *         whose pendingRoute is set by a notification tap.
 * Outputs: none.
 * Run: rendered by CaseRoomApp as the app's root view.
 */

import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(PushCoordinator.self) private var pushCoordinator
    @State private var selectedTab: RootTab = .today
    @State private var presentedProposeTo: Int?

    enum RootTab: Hashable {
        case today, cases, sessions, profile
    }

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                TabView(selection: $selectedTab) {
                    TodayView(selectedTab: $selectedTab)
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
                .onChange(of: pushCoordinator.pendingRoute) { _, newRoute in
                    guard let newRoute else { return }
                    switch newRoute {
                    case .proposeTo(let userId):
                        selectedTab = .today
                        presentedProposeTo = userId
                    case .proposals, .session:
                        selectedTab = .sessions
                    }
                    pushCoordinator.pendingRoute = nil
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
        .task {
            await sessionStore.bootstrap()
        }
    }
}

#Preview {
    RootTabView()
        .environment(SessionStore())
        .environment(PushCoordinator())
}
