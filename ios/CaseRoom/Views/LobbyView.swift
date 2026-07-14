/*
 * Purpose: Lobby screen — knock/admit/deny + consent toggles, rendered
 *          per-role (candidate vs. interviewer) from SessionViewModel's state.
 * Inputs: SessionViewModel (loaded + WS-connected by the host SessionView).
 * Outputs: none.
 * Run: shown by SessionView while state is scheduled/lobby.
 */

import SwiftUI

struct LobbyView: View {
    var viewModel: SessionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let otherPartyName {
                    Text("with \(otherPartyName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                roleSection

                consentSection

                if viewModel.role == "interviewer" {
                    goLiveButton
                }
            }
            .padding()
        }
    }

    private var otherPartyName: String? {
        viewModel.role == "interviewer" ? viewModel.candidateName : viewModel.interviewerName
    }

    @ViewBuilder
    private var roleSection: some View {
        if viewModel.role == "candidate" {
            candidateSection
        } else if viewModel.role == "interviewer" {
            interviewerSection
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if viewModel.denied {
            VStack(alignment: .leading, spacing: 8) {
                Label("Your knock was declined", systemImage: "hand.raised.slash")
                    .foregroundStyle(.red)
                Button("Knock Again") {
                    Task { await viewModel.knock() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("BrandAccent"))
            }
        } else if viewModel.admitted {
            Label("Admitted — waiting for the session to start", systemImage: "checkmark.circle")
                .foregroundStyle(Color("BrandAccent"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button("Knock") {
                    Task { await viewModel.knock() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("BrandAccent"))
                Text("Waiting to be admitted")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var interviewerSection: some View {
        if viewModel.peerKnocked {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.knockerName ?? "Your candidate") is knocking")
                    .font(.headline)
                HStack {
                    Button("Admit") {
                        Task { await viewModel.admit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("BrandAccent"))
                    Button("Deny", role: .destructive) {
                        Task { await viewModel.deny() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            Text(viewModel.peerPresent ? "Candidate is in the lobby" : "Waiting for the candidate")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var consentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Consent to Record")
                .font(.headline)
            Toggle(
                "I consent",
                isOn: Binding(
                    get: { viewModel.myConsent },
                    set: { _ in Task { await viewModel.toggleConsent() } }
                )
            )
            Text(viewModel.peerConsent ? "Your peer has consented" : "Waiting on your peer's consent")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var goLiveButton: some View {
        Button("Go Live") {
            Task { await viewModel.goLive() }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("BrandAccent"))
        .disabled(!(viewModel.consentInterviewer && viewModel.consentCandidate))
    }
}

#Preview {
    LobbyView(
        viewModel: SessionViewModel(
            sessionId: 1, service: APIClient.shared, signaling: SignalingClient()
        )
    )
}
