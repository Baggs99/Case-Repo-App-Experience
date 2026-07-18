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
    // MARK: - F5-T3 (additive) — the negotiation stage VM, owned here so it
    // survives the negotiating→lobby state flip and can hold the "THEY KEPT
    // THEIR PICK" resolution on screen before the lobby.
    @State private var negotiationViewModel: NegotiationViewModel?

    @Environment(\.dismiss) private var dismiss

    private let service: SessionService
    private let flowService: SessionFlowService   // F5-T3 additive (negotiation endpoints)

    // signaling defaults to nil (rather than = SignalingClient()) because a
    // default argument expression can't call an actor-isolated initializer
    // even from within this @MainActor init — it's resolved in the body instead.
    @MainActor
    init(
        sessionId: Int,
        service: SessionService = APIClient.shared,
        signaling: SignalingChannel? = nil,
        flowService: SessionFlowService = APIClient.shared   // F5-T3 additive
    ) {
        self.service = service
        self.flowService = flowService
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
                setUpNegotiationIfNeeded()   // F5-T3
            }
            .onDisappear {
                Task { await viewModel.stop() }
            }
            .onChange(of: viewModel.role) { _, _ in
                setUpSubViewModelsIfNeeded()
            }
            // MARK: - F5-T3 (additive) — a peer proposed/countered/accepted;
            // re-fetch the negotiation view (from the stable host view, so the
            // refresh + resolution detection survive the negotiating→lobby flip
            // that would otherwise unmount NegotiationView).
            .onChange(of: viewModel.negotiationTick) { _, _ in
                setUpNegotiationIfNeeded()
                Task { await negotiationViewModel?.refresh(stampedCaseId: viewModel.caseId) }
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
        } else if holdingNegotiationResolution, let negotiationViewModel {
            // MARK: - F5-T3 — hold the candidate's negotiation resolution
            // ("THEY KEPT THEIR PICK") on screen through the negotiating→lobby
            // flip until they tap Begin (resolutionAcknowledged).
            NegotiationStageView(viewModel: negotiationViewModel, sessionViewModel: viewModel)
        } else {
            switch viewModel.state {
            case "scheduled", "lobby":
                LobbyView(viewModel: viewModel)
            // MARK: - F5-T3 — negotiation happens BEFORE the lobby: a case-less
            // session starts in "negotiating" and flips to "lobby" once a case
            // is stamped (B3 state machine, overrides the design's narrative).
            case "negotiating":
                negotiationContent
            case "live":
                liveContent
            // MARK: - F5-T5 — the light debrief. The candidate's released grade
            // lands under "finalized" too (the interviewer's finalize flips the
            // server state), so route both here for the candidate; the
            // interviewer dismisses on finalize (onChange below) and never lingers.
            case "debrief":
                DebriefView(sessionViewModel: viewModel, rubricViewModel: rubricViewModel,
                            flowService: flowService)
            case "finalized" where viewModel.role == "candidate":
                DebriefView(sessionViewModel: viewModel, rubricViewModel: rubricViewModel,
                            flowService: flowService)
            default:
                ContentUnavailableView("Session Finalized", systemImage: "checkmark.seal")
            }
        }
    }

    // MARK: - F5-T3 negotiation

    /// True while the candidate has an unacknowledged negotiation resolution —
    /// keeps NegotiationView mounted through the negotiating→lobby flip.
    private var holdingNegotiationResolution: Bool {
        guard let negotiationViewModel else { return false }
        return negotiationViewModel.resolution != nil && !negotiationViewModel.resolutionAcknowledged
    }

    @ViewBuilder
    private var negotiationContent: some View {
        if let negotiationViewModel {
            NegotiationStageView(viewModel: negotiationViewModel, sessionViewModel: viewModel)
        } else {
            ProgressView()
        }
    }

    /// Builds the negotiation VM once, wired to the injected flow service (the
    /// fixture stub under the screenshot hatch, APIClient otherwise).
    private func setUpNegotiationIfNeeded() {
        if negotiationViewModel == nil {
            negotiationViewModel = NegotiationViewModel(sessionId: viewModel.sessionId, service: flowService)
        }
    }

    // MARK: - F5-T4 dark LIVE refit (canvas 4a/4b)
    //
    // The live role views own the dark clock header + the compact striped peer
    // pane. On a remote session the real WebRTC surface (VideoCallView, restyled
    // dark — its RTC representable untouched) mounts above once local capture is
    // up; until then (and in the screenshot fixture, which never starts media)
    // the role view's own striped pane stands in for the peer feed.
    @ViewBuilder
    private var liveContent: some View {
        let remoteVideoActive = viewModel.mode == "remote" && viewModel.localCapture != nil
        VStack(spacing: 0) {
            if remoteVideoActive, let localCapture = viewModel.localCapture {
                VideoCallView(
                    capture: localCapture,
                    remoteMediaSlot: RemoteMediaSlot(trackHandle: viewModel.remoteTrack),
                    videoEnabled: viewModel.videoEnabled,
                    audioEnabled: viewModel.audioEnabled,
                    onToggleVideo: { viewModel.toggleVideo() },
                    onToggleAudio: { viewModel.toggleAudio() }
                )
                .frame(height: 300)
            } else if viewModel.mode == "remote", let mediaStartError = viewModel.mediaStartError {
                mediaRetry(mediaStartError)
            }
            roleLiveContent(showsInterviewerPane: viewModel.mode == "remote" && !remoteVideoActive)
        }
    }

    @ViewBuilder
    private func roleLiveContent(showsInterviewerPane: Bool) -> some View {
        if viewModel.role == "interviewer", let rubricViewModel {
            InterviewerLiveView(
                viewModel: rubricViewModel,
                peerName: peerName,
                showsInterviewerPane: showsInterviewerPane
            )
        } else if viewModel.role == "candidate", let exhibitsViewModel {
            CandidateLiveView(
                viewModel: exhibitsViewModel,
                caseTitle: viewModel.caseTitle,
                caseKicker: liveCaseKicker,
                peerName: peerName,
                showsInterviewerPane: showsInterviewerPane
            )
        } else {
            ProgressView()
        }
    }

    private func mediaRetry(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .dsText(.serif(14, italic: true))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.retryStartMedia() } }
        }
        .padding()
    }

    /// The live peer name (the interviewer sees the candidate; vice versa).
    private var peerName: String {
        (viewModel.role == "interviewer" ? viewModel.candidateName : viewModel.interviewerName) ?? "Your peer"
    }

    /// Case kicker (type · difficulty · source). No production source exists yet
    /// (not on SessionDetail), so the real live path shows none; the canvas 4a
    /// kicker is supplied directly by the DEBUG standalone fixture shot.
    private var liveCaseKicker: String? { nil }

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
