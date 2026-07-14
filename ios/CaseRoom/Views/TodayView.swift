/*
 * Purpose: Today tab — next-session card (taps to Sessions), streak card,
 *          and a "Browse cases" CTA (taps to Cases). Empty state when there's
 *          no upcoming session.
 * Inputs: TodayViewModel (default APIClient.shared); a binding to
 *         RootTabView's selectedTab so cards can switch tabs.
 * Outputs: none.
 * Run: shown as a tab by RootTabView.
 */

import SwiftUI

struct TodayView: View {
    @State private var viewModel = TodayViewModel()
    @Binding var selectedTab: RootTabView.RootTab

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.errorMessage != nil && viewModel.nextSession == nil {
            ContentUnavailableView(viewModel.errorMessage!, systemImage: "wifi.slash")
        } else {
            List {
                Section {
                    if let nextSession = viewModel.nextSession {
                        NextSessionCard(session: nextSession) {
                            selectedTab = .sessions
                        }
                    } else {
                        EmptyNextSessionCard {
                            selectedTab = .cases
                        }
                    }
                }

                Section {
                    StreakCard(streakWeeks: viewModel.streakWeeks)
                }

                Section {
                    Button {
                        selectedTab = .cases
                    } label: {
                        Label("Browse cases", systemImage: "folder")
                    }
                }
            }
        }
    }
}

private struct NextSessionCard: View {
    let session: SessionSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next Session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.caseTitle)
                    .font(.headline)
                Text("with \(session.otherUser)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let scheduledAt = session.scheduledAt {
                    Text(scheduledAt, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(Color("BrandAccent"))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyNextSessionCard: View {
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No upcoming sessions")
                .font(.headline)
            Text("Browse cases to schedule one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Browse cases", action: onTap)
                .buttonStyle(.borderedProminent)
                .tint(Color("BrandAccent"))
        }
        .padding(.vertical, 4)
    }
}

private struct StreakCard: View {
    let streakWeeks: Int

    var body: some View {
        HStack {
            Image(systemName: "flame")
                .foregroundStyle(Color("BrandAccent"))
            Text(streakWeeks == 1 ? "1 week streak" : "\(streakWeeks) week streak")
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TodayView(selectedTab: .constant(.today))
}
