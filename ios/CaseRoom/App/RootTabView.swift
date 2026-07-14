/*
 * Purpose: Root four-tab navigation shell for CaseRoom.
 * Inputs: none.
 * Outputs: none.
 * Run: rendered by CaseRoomApp as the app's root view.
 */

import SwiftUI

struct RootTabView: View {
    var body: some View {
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
    }
}

// Placeholder tab views — replaced with real implementations in Tasks 11-14.
struct TodayView: View {
    var body: some View { Text("Today") }
}

struct CasesListView: View {
    var body: some View { Text("Cases") }
}

struct SessionsView: View {
    var body: some View { Text("Sessions") }
}

struct ProfileView: View {
    var body: some View { Text("Profile") }
}

#Preview {
    RootTabView()
}
