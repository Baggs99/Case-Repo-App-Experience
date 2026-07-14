/*
 * Purpose: Drives the whole session screen — loads SessionDetail, connects
 *          the signaling WebSocket, drives knock/admit/deny/consent/go-live,
 *          finalizes the debrief, forwards inbound exhibit reveals to the
 *          candidate's ExhibitsViewModel, and runs the interviewer's room-
 *          recorder lifecycle — all via injectable SessionService +
 *          SignalingChannel + RoomRecording + RecordingUploading so tests
 *          never touch the network, a real socket, or the microphone.
 * Inputs: sessionId; SessionService (default APIClient.shared);
 *         SignalingChannel (default SignalingClient()); RoomRecording
 *         (default RoomRecorder()); RecordingUploading (default
 *         DefaultRecordingUploader()).
 * Outputs: none (in-memory state + outbound signaling frames, recorder
 *          start/stop, and a recording upload as side effects).
 * Run: instantiated by SessionView; call load() from .task, stop() from
 *      .onDisappear.
 */

import Foundation
import Observation

// Bridges SignalingClient (a @MainActor class) into an injectable protocol.
// Requirements are declared async so a synchronous, main-actor-isolated
// implementation can satisfy them regardless of the caller's isolation.
protocol SignalingChannel {
    func connect(sessionId: Int) async -> AsyncStream<SignalMessage>
    func send(_ data: Data) async
    func disconnect() async
}

extension SignalingClient: SignalingChannel {}

// Bridges RoomRecorder into an injectable protocol so tests can stub the
// mic/recorder lifecycle. Signatures must match RoomRecorder's exactly
// (start() is async to match its AVAudioSession/permission dance; stop()
// returns a non-optional URL, same as RoomRecorder's).
protocol RoomRecording {
    func start() async throws
    func stop() -> URL
}

extension RoomRecorder: RoomRecording {}

// Bridges the static RecordingUploader enum into an injectable instance
// protocol so tests can stub the upload without touching the network.
protocol RecordingUploading {
    func upload(fileURL: URL, sessionId: Int, service: SessionService) async throws
}

struct DefaultRecordingUploader: RecordingUploading {
    func upload(fileURL: URL, sessionId: Int, service: SessionService) async throws {
        try await RecordingUploader.upload(fileURL: fileURL, sessionId: sessionId, service: service)
    }
}

// Bridges ExhibitsViewModel into an injectable protocol so SessionViewModel
// can forward inbound reveals without owning the candidate's view model
// (SessionView owns it and assigns itself here) and so tests can spy on
// the forwarded call without a real network-backed ExhibitsViewModel.
// @MainActor to match ExhibitsViewModel's own isolation.
@MainActor
protocol ExhibitRevealReceiving {
    func handleReveal(exhibitId: Int, keyB64: String)
}

extension ExhibitsViewModel: ExhibitRevealReceiving {}

@Observable
@MainActor
final class SessionViewModel {
    let sessionId: Int

    var state: String = ""
    var role: String?
    var caseTitle: String?
    var interviewerName: String?
    var candidateName: String?

    var peerPresent = false
    var admitted = false
    var denied = false
    var peerKnocked = false
    var knockerName: String?

    var consentInterviewer = false
    var consentCandidate = false

    var finalized = false
    var releasedGrade: Double?

    var isLoading = false
    var errorMessage: String?

    /// Set by the hosting view to the candidate's ExhibitsViewModel so
    /// inbound .reveal signaling messages reach its decrypt path. nil for
    /// the interviewer (and for tests that don't exercise reveal routing).
    var exhibitReceiver: ExhibitRevealReceiving?

    private let service: SessionService
    private let signaling: SignalingChannel
    private let recorder: RoomRecording
    private let uploader: RecordingUploading
    private var listenTask: Task<Void, Never>?
    private var recordingStarted = false

    init(
        sessionId: Int, service: SessionService, signaling: SignalingChannel,
        recorder: RoomRecording = RoomRecorder(), uploader: RecordingUploading = DefaultRecordingUploader()
    ) {
        self.sessionId = sessionId
        self.service = service
        self.signaling = signaling
        self.recorder = recorder
        self.uploader = uploader
    }

    /// This user's own consent flag, resolved by role.
    var myConsent: Bool {
        role == "interviewer" ? consentInterviewer : consentCandidate
    }

    /// The other party's consent flag, resolved by role.
    var peerConsent: Bool {
        role == "interviewer" ? consentCandidate : consentInterviewer
    }

    // MARK: - Load + connect

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await service.sessionDetail(id: sessionId)
            await apply(detail)
        } catch {
            errorMessage = "Couldn't load this session. Try again."
        }
        await connectSignaling()
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        await signaling.disconnect()
    }

    private func apply(_ detail: SessionDetail) async {
        let previousState = state
        state = detail.state
        role = detail.yourRole
        caseTitle = detail.caseTitle
        interviewerName = detail.interviewerName
        candidateName = detail.candidateName
        consentInterviewer = detail.consentInterviewer
        consentCandidate = detail.consentCandidate

        // Interviewer-only: start the room recorder the moment the session
        // becomes live (covers both goLive() and reloading an already-live
        // session). Guarded so it only ever fires once per VM lifetime.
        if previousState != "live", state == "live", role == "interviewer", !recordingStarted {
            recordingStarted = true
            try? await recorder.start()
        }
    }

    private func connectSignaling() async {
        listenTask?.cancel()
        let stream = await signaling.connect(sessionId: sessionId)
        listenTask = Task { @MainActor [weak self] in
            for await message in stream {
                self?.handle(message)
            }
        }
    }

    private func handle(_ message: SignalMessage) {
        switch message {
        case .ok(_, let peerPresent, let admitted):
            self.peerPresent = peerPresent
            self.admitted = admitted
        case .knock(let displayName):
            peerKnocked = true
            knockerName = displayName
        case .admit:
            admitted = true
        case .deny:
            denied = true
        case .peerJoined:
            peerPresent = true
        case .peerLeft:
            peerPresent = false
        case .reveal(let exhibitId, let keyB64):
            exhibitReceiver?.handleReveal(exhibitId: exhibitId, keyB64: keyB64)
        case .pong, .unknown:
            break
        }
    }

    // MARK: - Actions

    /// Candidate action: knocks to request entry into the lobby.
    func knock() async {
        denied = false
        await signaling.send(SignalMessage.knock())
    }

    /// Interviewer action: admits the knocking candidate.
    func admit() async {
        peerKnocked = false
        await signaling.send(SignalMessage.admit())
    }

    /// Interviewer action: denies the knocking candidate.
    func deny() async {
        peerKnocked = false
        await signaling.send(SignalMessage.deny())
    }

    /// Toggles this user's own consent flag via POST /consent, then applies
    /// the flag from the returned session rather than flipping it locally.
    func toggleConsent() async {
        guard let role else { return }
        let newValue = role == "interviewer" ? !consentInterviewer : !consentCandidate
        do {
            let detail = try await service.setConsent(id: sessionId, consent: newValue)
            await apply(detail)
        } catch {
            errorMessage = "Couldn't update consent. Try again."
        }
    }

    /// Interviewer-only: transitions to "live". Only fires when both consent
    /// flags are true — guarded locally, though the server also 409s.
    func goLive() async {
        guard consentInterviewer && consentCandidate else { return }
        do {
            let detail = try await service.transition(id: sessionId, target: "live")
            await apply(detail)
        } catch {
            errorMessage = "Couldn't start the session. Try again."
        }
    }

    // MARK: - Debrief + finalize

    /// Interviewer-only: finalizes the session with an optional grade
    /// override (nil keeps the rubric's computed preview). Guarded locally
    /// to only fire in "debrief" — the server also 409s otherwise. Stops
    /// and uploads the room recording on success; a failed upload is
    /// swallowed so it never blocks finalize.
    func finalize(grade: Double?) async {
        guard state == "debrief" else { return }
        do {
            try await service.finalize(id: sessionId, grade: grade)
            finalized = true
            releasedGrade = grade
            if role == "interviewer" {
                let fileURL = recorder.stop()
                try? await uploader.upload(fileURL: fileURL, sessionId: sessionId, service: service)
            }
        } catch {
            errorMessage = "Couldn't finalize this session. Try again."
        }
    }
}
