/*
 * Purpose: Session host view — loads + connects a SessionViewModel, showing
 *          LobbyView while state is scheduled/lobby; live/debrief states get
 *          a placeholder filled in by later tasks.
 * Inputs: sessionId; SessionService (default APIClient.shared);
 *         SignalingChannel (default SignalingClient()).
 * Outputs: none.
 * Run: pushed to view a practice session (navigation wiring lands in a
 *      later task).
 */

import SwiftUI

struct SessionView: View {
    @State private var viewModel: SessionViewModel

    // signaling defaults to nil (rather than = SignalingClient()) because a
    // default argument expression can't call an actor-isolated initializer
    // even from within this @MainActor init — it's resolved in the body instead.
    @MainActor
    init(
        sessionId: Int,
        service: SessionService = APIClient.shared,
        signaling: SignalingChannel? = nil
    ) {
        _viewModel = State(
            initialValue: SessionViewModel(
                sessionId: sessionId, service: service, signaling: signaling ?? SignalingClient()
            )
        )
    }

    var body: some View {
        content
            .navigationTitle(viewModel.caseTitle ?? "Session")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .onDisappear {
                Task { await viewModel.stop() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.state.isEmpty {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage, viewModel.state.isEmpty {
            ContentUnavailableView(errorMessage, systemImage: "wifi.slash")
        } else if viewModel.state == "scheduled" || viewModel.state == "lobby" {
            LobbyView(viewModel: viewModel)
        } else {
            ContentUnavailableView("Session in Progress", systemImage: "person.2.wave.2")
        }
    }
}

#Preview {
    NavigationStack {
        SessionView(sessionId: 1)
    }
}
