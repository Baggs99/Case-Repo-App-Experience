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
import SwiftUI

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

    // MARK: - F5-T3 negotiation screenshot fixtures (canvas 4a nego)

    /// A case-less negotiating session row (state:"negotiating", caseId 0 — no
    /// case stamped yet). Role varies for the candidate vs interviewer shot.
    static func negotiatingDetail(role: String) -> SessionDetail {
        SessionDetail(
            id: 4040, interviewerId: 16, candidateId: 1, caseId: 0,
            state: "negotiating", mode: "remote",
            consentInterviewer: false, consentCandidate: false,
            scheduledAt: nil, startedAt: nil, endedAt: nil,
            interviewerName: "M. Lindqvist", candidateName: "Amara Osei",
            caseTitle: nil, yourRole: role
        )
    }

    /// The interviewer's round-1 pick, shown to the candidate (their pick).
    static let negoPick = NegotiatedCaseBrief(
        caseId: 91, title: "Low-cost carrier enters the Nordic market",
        caseType: "Market entry", difficulty: "D4")

    /// The candidate's countered case (their standing request).
    static let negoCounter = NegotiatedCaseBrief(
        caseId: 8, title: "EV charging — size the German market",
        caseType: "Market sizing", difficulty: "D3")

    static let negoRequest = RequestedCaseBrief(
        caseId: 8, title: "EV charging — size the German market", fromRole: "candidate")

    /// Candidate's turn: the interviewer has picked, no counter yet.
    static let negoCandidateView = NegotiationView(
        sessionId: 4040, sessionState: "negotiating", yourRole: "candidate",
        whoseTurn: "candidate", roundUsed: 1,
        currentPick: negoPick, candidateCounter: nil,
        candidateRequestedCase: negoRequest, pickSources: nil)

    /// The candidate's terminal view once the interviewer kept their pick over
    /// the counter (case stamped == negoPick.caseId, a counter existed).
    static let negoKeptView = NegotiationView(
        sessionId: 4040, sessionState: "lobby", yourRole: "candidate",
        whoseTurn: nil, roundUsed: 2,
        currentPick: negoPick, candidateCounter: negoCounter,
        candidateRequestedCase: negoRequest, pickSources: nil)

    /// Interviewer's opening view: no pick yet, pick sources present.
    static let negoInterviewerView = NegotiationView(
        sessionId: 4040, sessionState: "negotiating", yourRole: "interviewer",
        whoseTurn: "interviewer", roundUsed: 0,
        currentPick: nil, candidateCounter: nil,
        candidateRequestedCase: negoRequest,
        pickSources: PickSources(
            recommendedForCandidate: [
                Recommendation(caseId: 91, title: "Low-cost carrier enters the Nordic market",
                               caseType: "Market entry", difficulty: "D4",
                               why: "Sizing shows up in the quant", rule: nil),
                Recommendation(caseId: 12, title: "Retail bank — win back churned SMEs",
                               caseType: "Profitability", difficulty: "D3", why: nil, rule: nil),
                Recommendation(caseId: 33, title: "Med-device launch — EU pricing",
                               caseType: "Pricing", difficulty: "D5", why: nil, rule: nil),
            ],
            interviewerDoneSet: [
                NegotiatedCaseBrief(caseId: 77, title: "Airline loyalty program economics",
                                    caseType: "Profitability", difficulty: "D4"),
                NegotiatedCaseBrief(caseId: 88, title: "Coffee chain store expansion",
                                    caseType: "Market entry", difficulty: "D3"),
            ],
            libraryAllowed: true))

    static let negoCandidateService = NegoPreviewSessionService(detail: negotiatingDetail(role: "candidate"))
    static let negoInterviewerService = NegoPreviewSessionService(detail: negotiatingDetail(role: "interviewer"))
    static let negoCandidateFlow = NegoPreviewFlowService(view: negoCandidateView)
    static let negoInterviewerFlow = NegoPreviewFlowService(view: negoInterviewerView)
    static let negoSignaling = NegoPreviewSignaling()

    /// Standalone kept-pick surface (canvas 4a negoKept). The candidate's
    /// resolution only exists post-flip, so it isn't reachable through the
    /// SessionView state machine — this renders NegotiationView directly with a
    /// seeded resolution for the screenshot.
    @MainActor
    static func negoKeptStandalone() -> some View {
        NegotiationStageView(
            viewModel: NegotiationViewModel(fixtureView: negoKeptView, resolution: .keptPick),
            sessionViewModel: negoSessionVM(role: "candidate", caseId: negoPick.caseId))
    }

    /// A host SessionViewModel pre-populated for negotiation previews/shots
    /// (names + stamped case id) with no network.
    @MainActor
    static func negoSessionVM(role: String, caseId: Int) -> SessionViewModel {
        let vm = SessionViewModel(
            sessionId: 4040, service: negoCandidateService, signaling: negoSignaling)
        vm.role = role
        vm.interviewerName = "M. Lindqvist"
        vm.candidateName = "Amara Osei"
        vm.caseId = caseId
        return vm
    }
}

/// Preview fixtures referenced by NegotiationView's #Preview blocks.
enum NegotiationPreview {
    static let candidateDecide = SessionFixtures.negoCandidateView
    static let candidateKept = SessionFixtures.negoKeptView
    static let interviewerChoose = SessionFixtures.negoInterviewerView

    @MainActor
    static func sessionVM(role: String) -> SessionViewModel {
        SessionFixtures.negoSessionVM(role: role, caseId: role == "candidate" ? SessionFixtures.negoPick.caseId : 0)
    }
}

/// Stub SessionService for the negotiation shots — returns a canned negotiating
/// row; unused endpoints throw (never hit while the negotiation is on screen).
struct NegoPreviewSessionService: SessionService {
    enum StubError: Error { case unused }
    let detail: SessionDetail

    func sessionDetail(id: Int) async throws -> SessionDetail { detail }
    func joinConfig(id: Int) async throws -> JoinConfig { throw StubError.unused }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { detail }
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

/// Stub SessionFlowService for the negotiation shots — negotiation()/propose()
/// return the canned view; accept/swap/recap/feedback throw (never hit on the
/// screenshot path).
struct NegoPreviewFlowService: SessionFlowService {
    enum StubError: Error { case unused }
    let view: NegotiationView

    func negotiation(id: Int) async throws -> NegotiationView { view }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { view }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { throw StubError.unused }
    func swap(id: Int) async throws -> SwapInitiated { throw StubError.unused }
    func swapAccept(id: Int) async throws -> SwapAccepted { throw StubError.unused }
    func recaps() async throws -> [RecapListItem] { throw StubError.unused }
    func recapViewed(id: Int) async throws -> RecapViewedResult { throw StubError.unused }
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult { throw StubError.unused }
    func feedbackReport(id: Int) async throws -> FeedbackReport { throw StubError.unused }
}

/// No-op signaling for the negotiation shots — holds the stream open (no
/// frames, no finish) so the applied state stays put.
struct NegoPreviewSignaling: SignalingChannel {
    func connect(sessionId: Int) async -> AsyncStream<SignalMessage> {
        AsyncStream { _ in }
    }
    func send(_ data: Data) async {}
    func disconnect() async {}
    func sendSDP(_ description: SDP) {}
    func sendICE(_ candidate: ICECandidate?) {}
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
