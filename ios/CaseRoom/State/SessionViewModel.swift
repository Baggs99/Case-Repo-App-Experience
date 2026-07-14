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
    func sendSDP(_ description: SDP)
    func sendICE(_ candidate: ICECandidate?)
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

// Bridges the WebRTC media stack (RTCPeerConnectionWrapper + Negotiator +
// WebRTCMediaCapture, assembled by RemoteMediaSession) into an injectable
// protocol so the VM test runs without WebRTC. `capture` is exposed (beyond
// what negotiation itself needs) so SessionView can hand the local capture to
// VideoCallView's picture-in-picture preview.
@MainActor
protocol RemoteMediaControlling: AnyObject {
    func start(signaling: SignalingChannel, iceServers: [ICEServer], polite: Bool) async throws
    func handle(_ message: SignalMessage) async
    func setVideoEnabled(_ enabled: Bool)
    func setAudioEnabled(_ enabled: Bool)
    var onRemoteTrack: (@MainActor (MediaTrackHandle) -> Void)? { get set }
    var capture: MediaCapturing? { get }
    func stop()
}

// Bridges LiveActivityController into an injectable protocol so tests can
// stub the ActivityKit lifecycle without a real Live Activity. @MainActor to
// match ActivityKit's Activity<T> (accessed from SwiftUI/app-lifecycle code).
@MainActor
protocol LiveActivityControlling: AnyObject {
    func start(sessionId: Int, initial: SessionActivityAttributes.ContentState) async
    func end() async
}

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

    /// Session mode from SessionDetail.mode ("remote" | "in_person") — gates
    /// whether the live transition wires up WebRTC media at all.
    var mode: String = ""
    var videoEnabled = true
    var audioEnabled = true
    var remoteTrack: MediaTrackHandle?
    var mediaStartError: String?

    /// Set by the hosting view to the candidate's ExhibitsViewModel so
    /// inbound .reveal signaling messages reach its decrypt path. nil for
    /// the interviewer (and for tests that don't exercise reveal routing).
    var exhibitReceiver: ExhibitRevealReceiving?

    private let service: SessionService
    private let signaling: SignalingChannel
    private let recorder: RoomRecording
    private let uploader: RecordingUploading
    private let makeRemoteMedia: @MainActor () -> RemoteMediaControlling
    private let liveActivity: LiveActivityControlling
    private var listenTask: Task<Void, Never>?
    private var recordingStarted = false
    private var mediaStarted = false
    private var liveActivityStarted = false
    private var liveActivityEnded = false
    private var media: RemoteMediaControlling?

    /// The local camera/mic capture backing the active remote media session,
    /// nil until media has started. Exposed so SessionView can hand it to
    /// VideoCallView's local preview without owning the media session itself.
    var localCapture: MediaCapturing? { media?.capture }

    init(
        sessionId: Int, service: SessionService, signaling: SignalingChannel,
        recorder: RoomRecording = RoomRecorder(), uploader: RecordingUploading = DefaultRecordingUploader(),
        makeRemoteMedia: @escaping @MainActor () -> RemoteMediaControlling = { RemoteMediaSession() },
        liveActivity: LiveActivityControlling = LiveActivityController()
    ) {
        self.sessionId = sessionId
        self.service = service
        self.signaling = signaling
        self.recorder = recorder
        self.uploader = uploader
        self.makeRemoteMedia = makeRemoteMedia
        self.liveActivity = liveActivity
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
        media?.stop()
        media = nil
        mediaStarted = false
        await endLiveActivityIfNeeded()
    }

    private func apply(_ detail: SessionDetail) async {
        let previousState = state
        state = detail.state
        role = detail.yourRole
        mode = detail.mode
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

        // Remote-mode only (in-person stays media-free); fires for both
        // roles. Live implies admitted, so the sdp/ice gate is respected
        // with no extra guard. Guarded so it only ever fires once per VM
        // lifetime.
        if previousState != "live", state == "live", mode == "remote", !mediaStarted {
            mediaStarted = true
            await startRemoteMedia()
        }

        // Leaving 'live' (debrief/finalized/aborted): stop camera+mic and
        // the peer connection immediately rather than waiting for stop()
        // (view disappear) — the candidate shouldn't keep streaming through
        // debrief grading. mediaStarted stays true: the session won't
        // re-enter live, so this only prevents a spurious restart.
        if previousState == "live", state != "live" {
            media?.stop()
            media = nil
        }

        // Fires for both roles and both modes (in-person and remote) — the
        // Live Activity is about the session lifecycle, not media. Guarded
        // so it only ever fires once per VM lifetime, including when the
        // initial load() lands directly on an already-lobby/live session.
        if (state == "lobby" || state == "live"), !liveActivityStarted {
            liveActivityStarted = true
            await liveActivity.start(sessionId: sessionId, initial: Self.makeLiveActivityContentState(detail))
        }

        if state == "finalized" {
            await endLiveActivityIfNeeded()
        }
    }

    private static func makeLiveActivityContentState(_ detail: SessionDetail) -> SessionActivityAttributes.ContentState {
        let counterpartName = (detail.yourRole == "interviewer" ? detail.candidateName : detail.interviewerName) ?? ""
        return SessionActivityAttributes.ContentState(
            state: detail.state, role: detail.yourRole ?? "", counterpartName: counterpartName,
            scheduledAt: detail.scheduledAt.map { iso8601Formatter.string(from: $0) },
            startedAt: detail.startedAt.map { iso8601Formatter.string(from: $0) }
        )
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func endLiveActivityIfNeeded() async {
        guard !liveActivityEnded else { return }
        liveActivityEnded = true
        await liveActivity.end()
    }

    private func startRemoteMedia() async {
        mediaStartError = nil
        let remoteMedia = makeRemoteMedia()
        remoteMedia.onRemoteTrack = { [weak self] handle in
            self?.remoteTrack = handle
        }
        media = remoteMedia
        do {
            let config = try await service.joinConfig(id: sessionId)
            try await remoteMedia.start(signaling: signaling, iceServers: config.iceServers, polite: role == "candidate")
        } catch {
            mediaStartError = "Couldn't start video. Try again."
        }
    }

    /// Retries a failed media start: clears the error, resets the
    /// once-per-lifetime guard, and re-invokes the media-start path.
    func retryStartMedia() async {
        mediaStartError = nil
        mediaStarted = false
        await startRemoteMedia()
    }

    private func connectSignaling() async {
        listenTask?.cancel()
        let stream = await signaling.connect(sessionId: sessionId)
        listenTask = Task { @MainActor [weak self] in
            for await message in stream {
                await self?.handle(message)
            }
        }
    }

    private func handle(_ message: SignalMessage) async {
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
        case .sessionUpdate:
            // A peer-driven state/consent change — re-fetch and re-apply so
            // this client advances (lobby->live->debrief->finalized, or sees
            // the peer's consent) without re-entering the screen. apply(_:)
            // is idempotent, so this is safe even if our own action already
            // triggered the same change.
            if let detail = try? await service.sessionDetail(id: sessionId) {
                await apply(detail)
            }
        case .sdp, .ice:
            // Media negotiation frames — routed to the remote-mode media
            // session's Negotiator. Only ever set for mode == "remote".
            await media?.handle(message)
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

    /// Video-off toggle: audio-only "phone-screen practice" mode for a
    /// remote session. No-op if media hasn't started (e.g. in-person).
    func toggleVideo() {
        videoEnabled.toggle()
        media?.setVideoEnabled(videoEnabled)
    }

    /// Mute toggle, for parity with toggleVideo().
    func toggleAudio() {
        audioEnabled.toggle()
        media?.setAudioEnabled(audioEnabled)
    }

    // MARK: - Debrief + finalize

    /// Interviewer-only: finalizes the session with an optional grade
    /// override (nil keeps the rubric's computed preview). Guarded locally
    /// to only fire for the interviewer role and in "debrief" — the server
    /// also 409s otherwise. Stops and uploads the room recording on success;
    /// a failed upload is swallowed so it never blocks finalize.
    func finalize(grade: Double?) async {
        guard role == "interviewer" else { return }
        guard state == "debrief" else { return }
        do {
            let result = try await service.finalize(id: sessionId, grade: grade)
            finalized = true
            releasedGrade = result.grade
            await endLiveActivityIfNeeded()
            if role == "interviewer" {
                let fileURL = recorder.stop()
                try? await uploader.upload(fileURL: fileURL, sessionId: sessionId, service: service)
            }
        } catch {
            errorMessage = "Couldn't finalize this session. Try again."
        }
    }
}
