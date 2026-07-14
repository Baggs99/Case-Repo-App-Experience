/*
 * Purpose: Root shell for CaseRoom — LoginView while logged out, four-tab
 *          navigation once authenticated.
 * Inputs: SessionStore (environment), whose bootstrap() checks the
 *         persisted session cookie on launch.
 * Outputs: none.
 * Run: rendered by CaseRoomApp as the app's root view.
 */

import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                TabView {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "sun.max") }

                    CasesListView()
                        .tabItem { Label("Cases", systemImage: "folder") }

                    SessionsView()
                        .tabItem { Label("Sessions", systemImage: "person.2.wave.2") }

                    ProfileView()
                        .tabItem { Label("You", systemImage: "person.crop.circle") }
                }
                .tint(Color("BrandAccent"))
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
}
