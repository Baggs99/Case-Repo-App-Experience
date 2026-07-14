/*
 * Purpose: Root shell for CaseRoom — LoginView while logged out, four-tab
 *          navigation once authenticated. Also routes notification taps:
 *          any pending push route selects the Sessions tab.
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

    enum RootTab: Hashable {
        case today, cases, sessions, profile
    }

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                TabView(selection: $selectedTab) {
                    TodayView()
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
                    guard newRoute != nil else { return }
                    selectedTab = .sessions
                    pushCoordinator.pendingRoute = nil
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

// Placeholder tab views — replaced with real implementations in Tasks 13-14.
struct TodayView: View {
    var body: some View { Text("Today") }
}

struct ProfileView: View {
    var body: some View { Text("Profile") }
}

#Preview {
    RootTabView()
        .environment(SessionStore())
        .environment(PushCoordinator())
}
