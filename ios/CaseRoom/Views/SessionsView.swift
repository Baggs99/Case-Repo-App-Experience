/*
 * Purpose: Sessions tab — proposals inbox (accept/decline, with a time
 *          picker when a proposal offers multiple slots) plus the list of
 *          upcoming scheduled sessions.
 * Inputs: SessionsViewModel (default APIClient.shared + EventKitCalendarWriter()).
 * Outputs: none.
 * Run: shown by RootShell for DSTab.caseTab.
 */

import SwiftUI

struct SessionsView: View {
    @State private var viewModel = SessionsViewModel()
    @State private var chosenTimes: [Int: Date] = [:]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Sessions")
                .toolbar(.hidden, for: .navigationBar)
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .alert(
                    "Couldn't Add to Calendar",
                    isPresented: Binding(
                        get: { viewModel.calendarError != nil },
                        set: { shown in if !shown { viewModel.calendarError = nil } }
                    )
                ) {
                    Button("OK") { viewModel.calendarError = nil }
                } message: {
                    Text(viewModel.calendarError ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.proposals.isEmpty && viewModel.upcoming.isEmpty {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(errorMessage, systemImage: "wifi.slash")
        } else {
            List {
                Section("Proposals") {
                    if viewModel.proposals.isEmpty {
                        Text("No pending proposals").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.proposals) { proposal in
                            ProposalRow(
                                proposal: proposal,
                                chosenTime: chosenTimeBinding(for: proposal),
                                onAccept: {
                                    let time = chosenTimes[proposal.id] ?? proposal.proposedTimes.first ?? Date()
                                    Task { await viewModel.accept(proposal, at: time) }
                                },
                                onDecline: {
                                    Task { await viewModel.decline(proposal) }
                                }
                            )
                        }
                    }
                }

                Section("Upcoming") {
                    if viewModel.upcoming.isEmpty {
                        Text("No upcoming sessions").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.upcoming) { session in
                            UpcomingRow(session: session)
                        }
                    }
                }

                Section("In-Person Pairing") {
                    NavigationLink("Create (Interviewer)") {
                        PairCreateView()
                    }
                    NavigationLink("Scan (Candidate)") {
                        PairScanView()
                    }
                }
            }
        }
    }

    private func chosenTimeBinding(for proposal: Proposal) -> Binding<Date> {
        Binding(
            get: { chosenTimes[proposal.id] ?? proposal.proposedTimes.first ?? Date() },
            set: { chosenTimes[proposal.id] = $0 }
        )
    }
}

private struct ProposalRow: View {
    let proposal: Proposal
    @Binding var chosenTime: Date
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposal.fromName)
                .font(.headline)
            Text(proposal.caseTitle ?? "Untitled case")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message = proposal.message {
                Text(message)
                    .font(.footnote)
            }
            if proposal.proposedTimes.count > 1 {
                Picker("Time", selection: $chosenTime) {
                    ForEach(proposal.proposedTimes, id: \.self) { time in
                        Text(time.formatted(date: .abbreviated, time: .shortened)).tag(time)
                    }
                }
                .pickerStyle(.menu)
            } else if let onlyTime = proposal.proposedTimes.first {
                Text(onlyTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("BrandAccent"))
                Button("Decline", role: .destructive, action: onDecline)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct UpcomingRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.caseTitle)
                .font(.headline)
            Text(session.otherUser)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let scheduledAt = session.scheduledAt {
                Text(scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SessionsView()
}
