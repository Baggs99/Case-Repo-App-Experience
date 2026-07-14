/*
 * Purpose: You (Profile) tab — user header, finalized-session count, streak,
 *          and Logout.
 * Inputs: SessionStore (environment); TodayViewModel (default
 *         APIClient.shared) for the finalized/streak stats.
 * Outputs: SessionStore.logout() side effect via the Logout button.
 * Run: shown as a tab by RootTabView.
 */

import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionStore.user?.name ?? "")
                            .font(.headline)
                        Text(sessionStore.user?.email ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Stats") {
                    HStack {
                        Text("Sessions finalized")
                        Spacer()
                        Text("\(viewModel.sessionsFinalized)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Streak", systemImage: "flame")
                        Spacer()
                        Text("\(viewModel.streakWeeks)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        Task { await sessionStore.logout() }
                    }
                }
            }
            .navigationTitle("You")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }
}

#Preview {
    ProfileView()
        .environment(SessionStore())
}
