/*
 * Purpose: Drives session entry + the lobby — loads SessionDetail, connects
 *          the signaling WebSocket, and reacts to inbound SignalMessages to
 *          drive knock/admit/deny/consent/go-live, via injectable
 *          SessionService + SignalingChannel so tests never touch the
 *          network or a real socket.
 * Inputs: sessionId; SessionService (default APIClient.shared);
 *         SignalingChannel (default SignalingClient()).
 * Outputs: none (in-memory state + outbound signaling frames as a side effect).
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

    var isLoading = false
    var errorMessage: String?

    private let service: SessionService
    private let signaling: SignalingChannel
    private var listenTask: Task<Void, Never>?

    init(sessionId: Int, service: SessionService, signaling: SignalingChannel) {
        self.sessionId = sessionId
        self.service = service
        self.signaling = signaling
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
            apply(detail)
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

    private func apply(_ detail: SessionDetail) {
        state = detail.state
        role = detail.yourRole
        caseTitle = detail.caseTitle
        interviewerName = detail.interviewerName
        candidateName = detail.candidateName
        consentInterviewer = detail.consentInterviewer
        consentCandidate = detail.consentCandidate
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
        case .reveal, .pong, .unknown:
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
            apply(detail)
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
            apply(detail)
        } catch {
            errorMessage = "Couldn't start the session. Try again."
        }
    }
}
