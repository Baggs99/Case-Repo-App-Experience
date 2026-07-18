/*
 * Purpose: Drives the F5 case-negotiation stage (canvas 4a nego) — loads the
 *          B3 negotiation view, proposes/counters/accepts through the
 *          SessionFlowService, and derives the role-specific stage (whose turn,
 *          counter-once gating, and the candidate's "THEY KEPT THEIR PICK"
 *          resolution when the interviewer keeps their round-1 pick over a
 *          counter). All turn/stage/resolution logic is a pure, file-scoped
 *          namespace (NegotiationLogic) so it unit-tests without a VM.
 * Inputs: sessionId; SessionFlowService (default APIClient.shared). The stamped
 *         case id (host SessionViewModel.caseId) is passed into refresh(_:) so
 *         the candidate can detect which case was accepted after the flip.
 * Outputs: none (in-memory state + network side effects).
 * Run: instantiated by SessionView for state == "negotiating"; refresh() on
 *      appear and on the host's negotiationTick (peer proposed/countered/accepted).
 */

import Foundation
import Observation

// MARK: - Pure logic (testable without a VM or network)

/// The candidate's terminal read of a resolved negotiation. Only meaningful
/// once a counter existed AND the case was stamped (negotiating → lobby):
/// keptPick = interviewer accepted their own round-1 pick over the counter;
/// tookCounter = interviewer accepted the candidate's counter.
enum NegotiationResolution: Equatable { case keptPick, tookCounter }

/// The candidate-side stage, derived from the B3 negotiation view + any
/// resolution. Drives which affordances NegotiationView renders.
enum CandidateNegoStage: Equatable {
    case waitingForPick                         // interviewer hasn't picked yet
    case decide(NegotiatedCaseBrief)            // their pick shown → accept or counter once
    case counterSent                            // counter used → awaiting their decision
    case keptPick(NegotiatedCaseBrief)          // "THEY KEPT THEIR PICK"
    case tookCounter(NegotiatedCaseBrief)       // they took the candidate's counter
}

/// The interviewer-side stage: pick from sources, await the candidate, or
/// resolve a counter (keep pick / take counter).
enum InterviewerNegoStage: Equatable {
    case choosePick(PickSources?)
    case awaitingCandidate(NegotiatedCaseBrief)
    case resolve(pick: NegotiatedCaseBrief, counter: NegotiatedCaseBrief)
}

enum NegotiationLogic {
    /// The candidate may act (accept/counter) only when the interviewer has
    /// picked, no counter has been used, and it is the candidate's turn — the
    /// same gate the server enforces in _nego_view (whose_turn == "candidate").
    static func candidateCanDecide(_ view: NegotiationView) -> Bool {
        view.currentPick != nil && view.candidateCounter == nil && view.whoseTurn == "candidate"
    }

    /// Detects the candidate's resolution once a case is stamped. Returns nil
    /// while the negotiation is still live or no counter was ever made (a plain
    /// accept of the pick with no counter is not a "kept pick" moment).
    static func resolution(view: NegotiationView, stampedCaseId: Int?) -> NegotiationResolution? {
        guard view.candidateCounter != nil, let stamped = stampedCaseId else { return nil }
        if stamped == view.currentPick?.caseId { return .keptPick }
        if stamped == view.candidateCounter?.caseId { return .tookCounter }
        return nil
    }

    /// The candidate stage. A resolution wins; otherwise derive from turn state.
    static func candidateStage(view: NegotiationView, resolution: NegotiationResolution?) -> CandidateNegoStage {
        if let resolution {
            switch resolution {
            case .keptPick:
                if let pick = view.currentPick { return .keptPick(pick) }
            case .tookCounter:
                if let counter = view.candidateCounter { return .tookCounter(counter) }
            }
        }
        guard let pick = view.currentPick else { return .waitingForPick }
        if view.candidateCounter != nil { return .counterSent }
        return .decide(pick)
    }

    /// The interviewer stage, derived from pick/counter presence.
    static func interviewerStage(view: NegotiationView) -> InterviewerNegoStage {
        guard let pick = view.currentPick else { return .choosePick(view.pickSources) }
        if let counter = view.candidateCounter { return .resolve(pick: pick, counter: counter) }
        return .awaitingCandidate(pick)
    }
}

// MARK: - View model

@Observable
@MainActor
final class NegotiationViewModel {
    let sessionId: Int
    private let service: SessionFlowService

    /// The latest negotiation view (nil until the first fetch lands).
    var view: NegotiationView?
    /// The candidate's resolution, once the case is stamped over a counter.
    var resolution: NegotiationResolution?
    /// Set by the resolution "Begin" affordance so the host stops holding the
    /// negotiation screen and falls through to the (already-flipped) lobby.
    var resolutionAcknowledged = false

    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?

    /// The stamped case id from the host session detail, cached from the last
    /// refresh so resolution() can compare it against the pick/counter.
    private var stampedCaseId: Int?

    init(sessionId: Int, service: SessionFlowService = APIClient.shared) {
        self.sessionId = sessionId
        self.service = service
    }

    // MARK: - Derived stages

    var candidateStage: CandidateNegoStage? {
        view.map { NegotiationLogic.candidateStage(view: $0, resolution: resolution) }
    }

    var interviewerStage: InterviewerNegoStage? {
        view.map { NegotiationLogic.interviewerStage(view: $0) }
    }

    // MARK: - Load / refresh

    /// (Re)fetches the negotiation view. `stampedCaseId` is the host session's
    /// current case id — nil while still negotiating, the accepted case once
    /// stamped — used to detect the candidate's resolution.
    func refresh(stampedCaseId: Int?) async {
        self.stampedCaseId = stampedCaseId
        if view == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fetched = try await service.negotiation(id: sessionId)
            apply(fetched)
        } catch {
            errorMessage = "Couldn't load the case negotiation. Try again."
        }
    }

    private func apply(_ fetched: NegotiationView) {
        view = fetched
        errorMessage = nil
        // Resolution is a candidate concern — the interviewer knows what they
        // did. Only compute (and never clear) it for the candidate side.
        if fetched.yourRole == "candidate", resolution == nil {
            resolution = NegotiationLogic.resolution(view: fetched, stampedCaseId: stampedCaseId)
        }
    }

    // MARK: - Actions

    /// Interviewer round-1 pick, or candidate's single counter — both POST the
    /// same /negotiation/propose route (the server assigns the round by role +
    /// state) and return a fresh negotiation view.
    func propose(caseId: Int) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let updated = try await service.proposeCase(id: sessionId, caseId: caseId)
            apply(updated)
        } catch {
            errorMessage = "Couldn't send that. Try again."
        }
    }

    /// Candidate: accept the interviewer's pick (candidate may accept ONLY the
    /// pick). Interviewer: resolve — pass currentPick.caseId to keep the pick,
    /// or candidateCounter.caseId to take the counter. Returns true when the
    /// case was stamped (negotiating → lobby) so the host can advance.
    @discardableResult
    func accept(caseId: Int) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await service.acceptCase(id: sessionId, caseId: caseId)
            return true
        } catch {
            errorMessage = "Couldn't lock in the case. Try again."
            return false
        }
    }

    /// The case id the candidate's Accept must use — always the interviewer's
    /// pick (server 403s any other choice for the candidate).
    var candidateAcceptCaseId: Int? { view?.currentPick?.caseId }

    #if DEBUG
    /// Screenshot/preview seed — a fully-formed view + resolution with no
    /// network. The stub service is never called on this path.
    convenience init(fixtureView: NegotiationView, resolution: NegotiationResolution?) {
        self.init(sessionId: fixtureView.sessionId, service: NegoPreviewFlowService(view: fixtureView))
        self.view = fixtureView
        self.resolution = resolution
    }
    #endif
}
