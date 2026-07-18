/*
 * Purpose: DEBUG-only fixtures for the dark session-takeover screenshots
 *          (F5 Task 2) — a stub SessionService that returns a `state:"lobby"`
 *          SessionDetail (candidate side, canvas 4a: You READY / M. Lindqvist
 *          JOINED) plus a no-op SignalingChannel, so `-startTakeover lobby`
 *          captures the dark lobby with no dev server and no live socket.
 * Inputs: none.
 * Outputs: SessionFixtures (lobbyDetail, lobbyService, noopSignaling).
 * Run: RootShell.takeoverSession(id:) binds SessionView to these under
 *      `-startTakeover`; CaseRoomApp.applyDebugLaunchHatches fakes auth +
 *      sets sessionTakeoverID for the same arg. Release-inert (#if DEBUG).
 */

#if DEBUG
import Foundation

enum SessionFixtures {

    /// Canvas 4a lobby, candidate side: both seated, You (candidate) has
    /// consented → READY; M. Lindqvist (interviewer) present, not yet consented
    /// → JOINED. Remote mode. No scheduled/started timestamps needed for the shot.
    static let lobbyDetail = SessionDetail(
        id: 4040,
        interviewerId: 16,
        candidateId: 1,
        caseId: 8,
        state: "lobby",
        mode: "remote",
        consentInterviewer: false,
        consentCandidate: true,
        scheduledAt: nil,
        startedAt: nil,
        endedAt: nil,
        interviewerName: "M. Lindqvist",
        candidateName: "Amara Osei",
        caseTitle: "EV charging — size the German market",
        yourRole: "candidate"
    )

    /// The session id the `-startTakeover` hatch presents.
    static let lobbySessionId = lobbyDetail.id

    static let lobbyService = LobbyPreviewSessionService()
    static let lobbySignaling = LobbyPreviewSignaling()
}

/// Stub SessionService for the lobby shot: `sessionDetail` returns the canned
/// lobby row; every other endpoint is unreachable on this screenshot path and
/// throws (never called while the lobby is on screen).
struct LobbyPreviewSessionService: SessionService {
    enum StubError: Error { case unused }

    func sessionDetail(id: Int) async throws -> SessionDetail { SessionFixtures.lobbyDetail }
    func joinConfig(id: Int) async throws -> JoinConfig { throw StubError.unused }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { SessionFixtures.lobbyDetail }
    func transition(id: Int, target: String) async throws -> SessionDetail { throw StubError.unused }
    func rubric(id: Int) async throws -> RubricState { throw StubError.unused }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { throw StubError.unused }
    func reveal(id: Int, exhibitId: Int) async throws { throw StubError.unused }
    func exhibits(id: Int) async throws -> [ExhibitMeta] { [] }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { throw StubError.unused }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { throw StubError.unused }
    func completeRecording(id: Int) async throws { throw StubError.unused }
    func finalize(id: Int, grade: Double?) async throws -> Finalized { throw StubError.unused }
}

/// Preview signaling for the shot: delivers one realistic `ok` frame (candidate
/// admitted, interviewer present) through the real VM path, then holds the
/// stream open. With the fixture's consentCandidate=true this lands You → READY
/// and M. Lindqvist → JOINED (canvas 4a) with no live socket.
struct LobbyPreviewSignaling: SignalingChannel {
    func connect(sessionId: Int) async -> AsyncStream<SignalMessage> {
        AsyncStream { continuation in
            continuation.yield(.ok(role: "candidate", peerPresent: true, admitted: true))
            // Left open (no finish) so the applied lobby state stays put for the shot.
        }
    }
    func send(_ data: Data) async {}
    func disconnect() async {}
    func sendSDP(_ description: SDP) {}
    func sendICE(_ candidate: ICECandidate?) {}
}
#endif
