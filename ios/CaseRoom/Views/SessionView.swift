/*
 * Purpose: Session host view — loads + connects a SessionViewModel and
 *          renders the right subview by state + role: scheduled/lobby ->
 *          LobbyView; live -> InterviewerLiveView or CandidateLiveView;
 *          debrief -> DebriefView; anything else -> a finalized summary.
 *          Owns the interviewer's RubricViewModel and the candidate's
 *          ExhibitsViewModel so the same instances back both the live view
 *          and (for the interviewer) DebriefView's grade preview, and so
 *          inbound reveals route into the candidate's ExhibitsViewModel.
 * Inputs: sessionId; SessionService (default APIClient.shared);
 *         SignalingChannel (default SignalingClient()).
 * Outputs: none.
 * Run: pushed to view a practice session (navigation wiring lands in a
 *      later task).
 */

import SwiftUI

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @State private var rubricViewModel: RubricViewModel?
    @State private var exhibitsViewModel: ExhibitsViewModel?

    @Environment(\.dismiss) private var dismiss

    private let service: SessionService

    // signaling defaults to nil (rather than = SignalingClient()) because a
    // default argument expression can't call an actor-isolated initializer
    // even from within this @MainActor init — it's resolved in the body instead.
    @MainActor
    init(
        sessionId: Int,
        service: SessionService = APIClient.shared,
        signaling: SignalingChannel? = nil
    ) {
        self.service = service
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
            .task {
                await viewModel.load()
                setUpSubViewModelsIfNeeded()
            }
            .onDisappear {
                Task { await viewModel.stop() }
            }
            .onChange(of: viewModel.role) { _, _ in
                setUpSubViewModelsIfNeeded()
            }
            .onChange(of: viewModel.finalized) { _, finalized in
                // The interviewer just finalized from DebriefView — dismiss.
                // The candidate stays to read the released grade.
                if finalized && viewModel.role == "interviewer" {
                    dismiss()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.state.isEmpty {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage, viewModel.state.isEmpty {
            ContentUnavailableView(errorMessage, systemImage: "wifi.slash")
        } else {
            switch viewModel.state {
            case "scheduled", "lobby":
                LobbyView(viewModel: viewModel)
            case "live":
                liveContent
            case "debrief":
                DebriefView(sessionViewModel: viewModel, rubricViewModel: rubricViewModel)
            default:
                ContentUnavailableView("Session Finalized", systemImage: "checkmark.seal")
            }
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        if viewModel.mode == "remote" {
            remoteLiveContent
        } else {
            roleLiveContent
        }
    }

    // Remote sessions: the video call is the primary surface, with the same
    // role view (rubric or exhibits) still reachable underneath so the
    // interviewer keeps scoring and the candidate keeps seeing exhibits
    // during the call. Polish (e.g. a picture-in-picture layout) is a later
    // pass.
    @ViewBuilder
    private var remoteLiveContent: some View {
        VStack(spacing: 0) {
            if let localCapture = viewModel.localCapture {
                VideoCallView(
                    capture: localCapture,
                    remoteMediaSlot: RemoteMediaSlot(trackHandle: viewModel.remoteTrack),
                    videoEnabled: viewModel.videoEnabled,
                    audioEnabled: viewModel.audioEnabled,
                    onToggleVideo: { viewModel.toggleVideo() },
                    onToggleAudio: { viewModel.toggleAudio() }
                )
                .frame(height: 320)
            } else if let mediaStartError = viewModel.mediaStartError {
                ContentUnavailableView {
                    Label(mediaStartError, systemImage: "video.slash")
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.retryStartMedia() }
                    }
                }
                .frame(height: 320)
            } else {
                ProgressView()
                    .frame(height: 320)
            }
            roleLiveContent
        }
    }

    @ViewBuilder
    private var roleLiveContent: some View {
        if viewModel.role == "interviewer", let rubricViewModel {
            InterviewerLiveView(viewModel: rubricViewModel)
        } else if viewModel.role == "candidate", let exhibitsViewModel {
            CandidateLiveView(viewModel: exhibitsViewModel)
        } else {
            ProgressView()
        }
    }

    // Lazily builds the role-appropriate sub view model exactly once, and
    // (for the candidate) wires it as SessionViewModel's reveal target so an
    // inbound .reveal SignalMessage reaches its decrypt path.
    private func setUpSubViewModelsIfNeeded() {
        switch viewModel.role {
        case "interviewer":
            if rubricViewModel == nil {
                rubricViewModel = RubricViewModel(sessionId: viewModel.sessionId, service: service)
            }
        case "candidate":
            if exhibitsViewModel == nil {
                let exhibits = ExhibitsViewModel(sessionId: viewModel.sessionId, service: service)
                exhibitsViewModel = exhibits
                viewModel.exhibitReceiver = exhibits
            }
        default:
            break
        }
    }
}

#Preview {
    NavigationStack {
        SessionView(sessionId: 1)
    }
}
