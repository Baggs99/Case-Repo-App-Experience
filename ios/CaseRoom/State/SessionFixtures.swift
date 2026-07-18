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
import CryptoKit
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

    // MARK: - F5-T4 live screenshot fixtures (canvas 4a live + 4b exhibit open)

    static let liveExhibitId = 501
    static let liveCaseTitle = "Low-cost carrier enters the Nordic market"
    static let liveKicker = "MARKET ENTRY · D4 · KELLOGG 2019"

    /// A live, remote session row. Names match the takeover persona (Amara Osei
    /// vs M. Lindqvist). Role varies for the candidate vs interviewer shot.
    static func liveDetail(role: String) -> SessionDetail {
        SessionDetail(
            id: 4040, interviewerId: 16, candidateId: 1, caseId: 91,
            state: "live", mode: "remote",
            consentInterviewer: true, consentCandidate: true,
            scheduledAt: nil, startedAt: nil, endedAt: nil,
            interviewerName: "M. Lindqvist", candidateName: "Amara Osei",
            caseTitle: liveCaseTitle, yourRole: role)
    }

    // Fixed key/nonce → a real AES-GCM ciphertext the untouched ExhibitCrypto
    // decrypt path opens (exercises the reveal seam byte-for-byte, no server).
    private static let liveKeyData = Data((0..<32).map { UInt8(($0 &* 7 &+ 11) & 0xFF) })
    private static let liveIVData  = Data((0..<12).map { UInt8(($0 &* 5 &+ 3) & 0xFF) })
    static let liveExhibitKeyB64 = liveKeyData.base64EncodedString()
    static let liveExhibitIVB64  = liveIVData.base64EncodedString()

    private static let liveExhibitJSON = """
    {
      "title": "Nordic domestic market — volumes & fares",
      "releasedAt": "11:58",
      "table": {
        "columns": ["COUNTRY", "PAX / YR", "AVG FARE"],
        "rows": [
          { "cells": ["Norway", "6.1M", "€92"], "total": false },
          { "cells": ["Sweden", "5.2M", "€97"], "total": false },
          { "cells": ["Finland", "2.7M", "€99"], "total": false },
          { "cells": ["Total", "14.0M", "€95"], "total": true }
        ]
      },
      "bars": {
        "title": "Competitor unit costs — € cents per seat-km",
        "scaleMax": 7.0,
        "items": [
          { "label": "Skanwing", "value": 4.1, "highlight": true },
          { "label": "NorAir", "value": 5.3, "highlight": false },
          { "label": "FinnJet", "value": 6.0, "highlight": false }
        ],
        "footnote": "Rotate the phone to read a full-page exhibit."
      }
    }
    """

    static let liveExhibitPlaintext = Data(liveExhibitJSON.utf8)

    /// ciphertext||tag, the layout ExhibitCrypto.decrypt expects.
    static let liveExhibitBlob: Data = {
        let sealed = try! AES.GCM.seal(
            liveExhibitPlaintext,
            using: SymmetricKey(data: liveKeyData),
            nonce: try! AES.GCM.Nonce(data: liveIVData))
        return sealed.ciphertext + sealed.tag
    }()

    static let liveExhibitMeta = ExhibitMeta(
        exhibitId: liveExhibitId, idx: 0, sourcePages: "2",
        width: 1200, height: 800, bytes: liveExhibitBlob.count, ivB64: liveExhibitIVB64)

    /// The interviewer's live rubric — 4 dimensions (canvas debrief bars 8/6/8/7,
    /// avg 7.2), so the ScoreCells strips and the running-average readout fill.
    static let liveRubric = RubricState(
        templateItems: [
            RubricTemplateItem(id: "structure", label: "Structure", dimension: "structure", maxPoints: 10),
            RubricTemplateItem(id: "quant", label: "Quant", dimension: "quant", maxPoints: 10),
            RubricTemplateItem(id: "comm", label: "Communication", dimension: "comm", maxPoints: 10),
            RubricTemplateItem(id: "synth", label: "Synthesis", dimension: "synth", maxPoints: 10),
        ],
        items: [
            "structure": RubricItemScore(points: 8, note: "Clean issue tree, MECE branches"),
            "quant": RubricItemScore(points: 6, note: "Sizing setup slow to land"),
            "comm": RubricItemScore(points: 8, note: "Signposted well"),
            "synth": RubricItemScore(points: 7, note: "So-what landed at the close"),
        ],
        notesMd: "Strong opener. Trust the sizing sooner.",
        gradePreview: 7.2, grade: nil, finalizedAt: nil)

    @MainActor static func liveExhibitsVM() -> ExhibitsViewModel {
        ExhibitsViewModel(sessionId: 4040, service: LivePreviewSessionService(detail: liveDetail(role: "candidate")))
    }

    @MainActor static func liveRubricVM() -> RubricViewModel {
        RubricViewModel(sessionId: 4040, service: LivePreviewSessionService(detail: liveDetail(role: "interviewer")))
    }

    /// Standalone candidate LIVE (canvas 4a/4b). Rendered directly — a live,
    /// remote SessionView would auto-start real WebRTC on load, which the
    /// simulator can't and this task must not touch; the reveal is instead
    /// driven straight into the (unchanged) decrypt path after the view's own
    /// load() has fetched the ciphertext. openExhibit=true → the 4b held-still
    /// exhibit-open frame (no toast); false → CASE tab with the EX new-dot + toast.
    @MainActor static func liveCandidateStandalone(openExhibit: Bool) -> some View {
        LiveCandidateStandalone(viewModel: liveExhibitsVM(), openExhibit: openExhibit)
    }

    @MainActor static func liveInterviewerStandalone() -> some View {
        InterviewerLiveView(viewModel: liveRubricVM(), peerName: "Amara Osei", showsInterviewerPane: true)
    }

    // MARK: - F5-T5 debrief screenshot fixtures (canvas 4a debrief, LIGHT)

    /// The released feedback report shown in the candidate debrief: 7.2 avg over
    /// 4 dimensions (Structure 8 / Quant 6 / Communication 8 / Synthesis 7 — the
    /// canvas bars), the serif feedback line, attributed to M. Lindqvist.
    static let debriefReport = FeedbackReport(
        grade: 7.2,
        finalizedAt: "2026-07-16T21:04:00Z",
        notesMd: "The €90M so-what landed. Next time, get there ninety seconds sooner — the sizing setup cost you the close.",
        items: [
            FeedbackItem(id: "structure", label: "Structure", dimension: "structure", maxPoints: 10, points: 8, note: "Clean issue tree, MECE branches"),
            FeedbackItem(id: "quant", label: "Quant", dimension: "quant", maxPoints: 10, points: 6, note: "Sizing setup slow to land"),
            FeedbackItem(id: "comm", label: "Communication", dimension: "comm", maxPoints: 10, points: 8, note: "Signposted well"),
            FeedbackItem(id: "synth", label: "Synthesis", dimension: "synth", maxPoints: 10, points: 7, note: "So-what landed at the close"),
        ],
        reveals: [],
        caseId: 91,
        caseTitle: "Low-cost carrier enters the Nordic market")

    /// A finalized session row for the debrief shot (role varies).
    static func debriefDetail(role: String) -> SessionDetail {
        SessionDetail(
            id: 4040, interviewerId: 16, candidateId: 1, caseId: 91,
            state: role == "interviewer" ? "debrief" : "finalized", mode: "remote",
            consentInterviewer: true, consentCandidate: true,
            scheduledAt: nil, startedAt: nil, endedAt: nil,
            interviewerName: "M. Lindqvist", candidateName: "Amara Osei",
            caseTitle: liveCaseTitle, yourRole: role)
    }

    static let debriefCandidateFlow = DebriefPreviewFlowService(report: debriefReport)
    static let debriefInterviewerFlow = DebriefPreviewFlowService(report: nil)

    /// A host SessionViewModel pre-populated for the debrief shot (names + the
    /// interviewer id the candidate's Schedule-next prefills), with no network.
    @MainActor
    static func debriefSessionVM(role: String) -> SessionViewModel {
        let vm = SessionViewModel(
            sessionId: 4040,
            service: LivePreviewSessionService(detail: debriefDetail(role: role)),
            signaling: NegoPreviewSignaling())
        vm.role = role
        vm.state = debriefDetail(role: role).state
        vm.interviewerId = 16
        vm.interviewerName = "M. Lindqvist"
        vm.candidateName = "Amara Osei"
        vm.caseTitle = liveCaseTitle
        if role == "candidate" { vm.finalized = true; vm.releasedGrade = 7.2 }
        return vm
    }

    /// Standalone candidate debrief (canvas 4a debrief, LIGHT). Rendered inside
    /// the dark takeover cover by the `-startTakeover debrief` hatch, so it also
    /// proves the .dsTheme(.light) override wins over the inherited dark seam.
    @MainActor
    static func debriefCandidateStandalone() -> some View {
        DebriefView(sessionViewModel: debriefSessionVM(role: "candidate"),
                    flowService: debriefCandidateFlow)
    }

    /// Standalone interviewer debrief (grade preview / override / Finalize + Swap).
    @MainActor
    static func debriefInterviewerStandalone() -> some View {
        DebriefView(sessionViewModel: debriefSessionVM(role: "interviewer"),
                    rubricViewModel: liveRubricVM(),
                    flowService: debriefInterviewerFlow)
    }

    // MARK: - F5-T6 recap report screenshot fixtures (canvas 6b, LIGHT)

    /// The session the `-startRecap` hatch presents (T. Becker's Ski resort recap
    /// — the PreviewRecap persona: 4.1/5, "Structure held. The quant went soft…").
    static let recapSessionId = 5150

    /// The five serif paragraphs T. Becker wrote (canvas 6b, verbatim), carried
    /// in notes_md (blank-line separated → RecapPresentation.paragraphs). The
    /// rubric items score 7/5/8/6 out of 10 (canvas bar widths 70/50/80/60%);
    /// their per-item notes are left empty so the report is the pure prose block
    /// the canvas shows — the notes-present path is exercised by unit tests.
    static let recapReport = FeedbackReport(
        grade: 4.1,
        finalizedAt: "2026-07-12T16:34:00Z",
        notesMd: [
            "Your opening was the best I've seen from you — answer-first, three branches, and you told me which one you'd start with before I asked. Structure held for the whole case.",
            "The quant went soft in the middle. The lift-ticket yield calculation had a units slip — per-day versus per-visitor — and you carried it for two minutes before sanity-checking. You caught it yourself, which matters, but the recovery cost you the pace of the whole segment.",
            "When the margin bridge finally came together, your so-what was right: mix shift to day-trippers, not costs. You should have said it ninety seconds earlier with half the arithmetic. The insight was cheap; you paid full price.",
            "Close was clean but thin — one risk, no next step. Steal the last two minutes back from the quant and spend them there.",
            "Drill sizing setups until the units are automatic. Thursday's dental case is quant-heavy on purpose.",
        ].joined(separator: "\n\n"),
        items: [
            FeedbackItem(id: "structure", label: "Structure", dimension: "structure", maxPoints: 10, points: 7, note: ""),
            FeedbackItem(id: "quant", label: "Quant", dimension: "quant", maxPoints: 10, points: 5, note: ""),
            FeedbackItem(id: "comm", label: "Communication", dimension: "comm", maxPoints: 10, points: 8, note: ""),
            FeedbackItem(id: "synth", label: "Synthesis", dimension: "synth", maxPoints: 10, points: 6, note: ""),
        ],
        reveals: [],
        caseId: 55,
        caseTitle: "Ski resort: revenue up, profit down")

    /// The matching unread-recap row — the source of the interviewer name + /5
    /// rating the feedback endpoint doesn't carry (RecapViewModel enriches from
    /// recaps()).
    static let recapListItem = RecapListItem(
        sessionId: recapSessionId, caseId: 55,
        caseTitle: "Ski resort: revenue up, profit down",
        interviewerName: "T. Becker", grade: 4.1,
        finalizedAt: "2026-07-12T16:34:00Z", viewedAt: nil)

    static let recapFlow = RecapPreviewFlowService(report: recapReport, recaps: [recapListItem])

    /// Standalone recap report (canvas 6b, LIGHT). Presented by RootShell's recap
    /// cover under `-startRecap`, with no dev server and no live socket.
    @MainActor
    static func recapStandalone() -> some View {
        RecapReportView(sessionId: recapSessionId, flowService: recapFlow)
    }
}

/// Drives the LIVE candidate shot: hands CandidateLiveView the shared VM, then
/// (after its load fetches the ciphertext) reveals through the real decrypt seam.
struct LiveCandidateStandalone: View {
    let viewModel: ExhibitsViewModel
    let openExhibit: Bool

    var body: some View {
        CandidateLiveView(
            viewModel: viewModel,
            caseTitle: SessionFixtures.liveCaseTitle,
            caseKicker: SessionFixtures.liveKicker,
            peerName: "M. Lindqvist",
            showsInterviewerPane: true,
            autoOpenOnReveal: openExhibit
        )
        .task {
            // CandidateLiveView.task loads the manifest + blobs; give it a beat,
            // then reveal (fixture key → ExhibitCrypto) so the shot has content.
            try? await Task.sleep(nanoseconds: 900_000_000)
            viewModel.handleReveal(exhibitId: SessionFixtures.liveExhibitId, keyB64: SessionFixtures.liveExhibitKeyB64)
        }
    }
}

/// Stub SessionService for the live shots — serves the canned live row, the one
/// Nordic exhibit (manifest + ciphertext), and the interviewer rubric; unused
/// endpoints throw (never hit on the screenshot path).
struct LivePreviewSessionService: SessionService {
    enum StubError: Error { case unused }
    let detail: SessionDetail

    func sessionDetail(id: Int) async throws -> SessionDetail { detail }
    func joinConfig(id: Int) async throws -> JoinConfig { throw StubError.unused }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { detail }
    func transition(id: Int, target: String) async throws -> SessionDetail { detail }
    func rubric(id: Int) async throws -> RubricState { SessionFixtures.liveRubric }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { SessionFixtures.liveRubric.gradePreview }
    func reveal(id: Int, exhibitId: Int) async throws {}
    func exhibits(id: Int) async throws -> [ExhibitMeta] { [SessionFixtures.liveExhibitMeta] }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { SessionFixtures.liveExhibitBlob }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws {}
    func completeRecording(id: Int) async throws {}
    func finalize(id: Int, grade: Double?) async throws -> Finalized { throw StubError.unused }
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

/// Stub SessionFlowService for the debrief shots — feedbackReport() returns the
/// canned released report (nil = the pre-release "waiting" path); recapClose/swap
/// return canned success so the shot's rating/swap affordances are live; the rest
/// throw (never hit on the screenshot path).
struct DebriefPreviewFlowService: SessionFlowService {
    enum StubError: Error { case unused }
    let report: FeedbackReport?

    func negotiation(id: Int) async throws -> NegotiationView { throw StubError.unused }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { throw StubError.unused }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { throw StubError.unused }
    func swap(id: Int) async throws -> SwapInitiated { SwapInitiated(swapInviteId: 1, inviteeId: 16) }
    func swapAccept(id: Int) async throws -> SwapAccepted { throw StubError.unused }
    func recaps() async throws -> [RecapListItem] { throw StubError.unused }
    func recapViewed(id: Int) async throws -> RecapViewedResult { throw StubError.unused }
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult {
        RecapCloseResult(closed: true, gateCleared: true)
    }
    func feedbackReport(id: Int) async throws -> FeedbackReport {
        guard let report else { throw StubError.unused }
        return report
    }
}

/// Stub SessionFlowService for the recap report shot — feedbackReport() returns
/// the canned released report and recaps() the matching unread row (so the
/// attribution enriches); recapViewed() succeeds (candidate marks it read); the
/// rest throw (never hit on the screenshot path).
struct RecapPreviewFlowService: SessionFlowService {
    enum StubError: Error { case unused }
    let report: FeedbackReport
    let recaps: [RecapListItem]

    func negotiation(id: Int) async throws -> NegotiationView { throw StubError.unused }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView { throw StubError.unused }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail { throw StubError.unused }
    func swap(id: Int) async throws -> SwapInitiated { throw StubError.unused }
    func swapAccept(id: Int) async throws -> SwapAccepted { throw StubError.unused }
    func recaps() async throws -> [RecapListItem] { recaps }
    func recapViewed(id: Int) async throws -> RecapViewedResult { RecapViewedResult(viewed: true) }
    // F5-T7: canned success so the close-out sheet's Close clears the gate on the
    // `-startRecap unlocked/cleared` shots (gate_cleared true).
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult {
        RecapCloseResult(closed: true, gateCleared: true)
    }
    func feedbackReport(id: Int) async throws -> FeedbackReport { report }
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
