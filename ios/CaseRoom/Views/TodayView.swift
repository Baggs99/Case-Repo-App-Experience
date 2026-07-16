/*
 * Purpose: Today tab — drill-of-the-day card (taps to open the drill sheet),
 *          a free-now toggle with a list of classmates free now (taps open the
 *          propose-now sheet), next-session card (taps to Sessions), streak
 *          card, and a "Browse cases" CTA. Empty state when no upcoming session.
 * Inputs: TodayViewModel (default APIClient.shared); SessionStore (environment,
 *         for the drill engine's user seed); a binding to RootTabView's
 *         selectedTab so cards can switch tabs.
 * Outputs: none.
 * Run: shown as a tab by RootTabView.
 */

import SwiftUI

struct TodayView: View {
    @State private var viewModel = TodayViewModel()
    @State private var freeNowViewModel = FreeNowViewModel()
    @State private var drillViewModel: DrillViewModel?
    @State private var drillCompleted = false
    @State private var proposeTo: FreeUser?
    @Environment(SessionStore.self) private var sessionStore
    @Binding var selectedTab: RootTabView.RootTab

    private var freeBinding: Binding<Bool> {
        Binding(
            get: { freeNowViewModel.isFree },
            set: { _ in Task { await freeNowViewModel.toggle() } }
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
                .task {
                    // Best-effort template refresh so the on-device FM engine has
                    // an offline pack; run alongside the dashboard load.
                    async let refresh: Void = TemplateCache().refresh(service: APIClient.shared)
                    async let freeNow: Void = freeNowViewModel.refresh()
                    await viewModel.load()
                    await refresh
                    await freeNow
                }
                .refreshable {
                    await viewModel.load()
                    await freeNowViewModel.refresh()
                }
                .sheet(item: $drillViewModel, onDismiss: handleDrillDismiss) {
                    DrillView(viewModel: $0)
                }
        }
    }

    private func startDrill() {
        drillCompleted = false
        let drill = DrillViewModel(
            engine: DrillEngineProvider.make(
                service: APIClient.shared, userId: sessionStore.user?.id ?? 0
            ),
            recorder: AttemptRecorder(service: APIClient.shared)
        )
        // Flags graded completion for the dismissal handler — the sheet item is
        // already nil by the time onDismiss runs, so the VM can't be read there.
        drill.onAnswered = { drillCompleted = true }
        drillViewModel = drill
    }

    private func handleDrillDismiss() {
        viewModel.drillSheetDismissed(completed: drillCompleted)
        drillCompleted = false
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.errorMessage != nil && viewModel.nextSession == nil {
            ContentUnavailableView(viewModel.errorMessage!, systemImage: "wifi.slash")
        } else {
            List {
                Section {
                    DrillCard(
                        drillDoneToday: viewModel.drillDoneToday,
                        streakDays: viewModel.streakDays,
                        onTap: startDrill
                    )
                }

                Section {
                    Toggle(isOn: freeBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Free to practice now")
                                .font(.headline)
                            if freeNowViewModel.isFree, let freeUntil = freeNowViewModel.freeUntil {
                                Text("Broadcasting until \(freeUntil, style: .time)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Let classmates know you're available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(Color("BrandAccent"))
                }

                if !freeNowViewModel.others.isEmpty {
                    Section(freeNowCountLabel) {
                        ForEach(freeNowViewModel.others) { user in
                            Button {
                                proposeTo = user
                            } label: {
                                FreeUserRow(user: user)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

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
            .sheet(item: $proposeTo) { user in
                ProposeNowView(toUser: user.userId, toName: user.name)
            }
        }
    }

    private var freeNowCountLabel: String {
        freeNowViewModel.others.count == 1
            ? "1 classmate free now"
            : "\(freeNowViewModel.others.count) classmates free now"
    }
}

private struct FreeUserRow: View {
    let user: FreeUser

    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Color("BrandAccent"))
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.headline)
                Text("Free until \(user.freeUntil, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Propose")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("BrandAccent"))
        }
        .padding(.vertical, 2)
    }
}

private struct DrillCard: View {
    let drillDoneToday: Bool
    let streakDays: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Drill of the day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if drillDoneToday {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color("BrandAccent"))
                        Text("Completed today")
                            .font(.headline)
                    } else {
                        Text("Start today's drill")
                            .font(.headline)
                            .foregroundStyle(Color("BrandAccent"))
                    }
                    Spacer()
                    Image(systemName: "flame")
                        .foregroundStyle(Color("BrandAccent"))
                    Text("\(streakDays)")
                        .font(.headline)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
        .environment(SessionStore())
}
