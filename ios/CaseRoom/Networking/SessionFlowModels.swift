/*
 * Purpose: Codable models mirroring the B3 session-flow JSON contracts (F5
 *          Task 1) — case negotiation, role swap, feedback recap gate, and the
 *          released feedback report. Shapes verified field-by-field against
 *          webapp/routes/session_flow.py and webapp/routes/practice_feedback.py.
 * Inputs: JSON decoded by APIClient via JSONDecoder.convertFromSnakeCase.
 * Outputs: none (pure data types).
 * Run: consumed by ios/CaseRoom/Networking/APIClient.swift SessionFlowService.
 */

import Foundation

// MARK: - F5 Negotiation

// A case as it appears inside a negotiation round or a pick-source list —
// session_flow.py _case_brief() and nego_repo.interviewer_done_set(). `title`
// is cases.case_title (non-null); difficulty is the case's text bucket
// (cases.difficulty is text — String?, NOT the numeric difficulty_score).
struct NegotiatedCaseBrief: Codable, Equatable {
    let caseId: Int
    let title: String
    let caseType: String?
    let difficulty: String?
}

// The case that the originating proposal carried (candidate's request), when
// present — nego_repo.originating_requested_case(). DISTINCT from
// NegotiatedCaseBrief: it has no case_type/difficulty but adds from_role.
struct RequestedCaseBrief: Codable, Equatable {
    let caseId: Int
    let title: String
    let fromRole: String
}

// Interviewer-only pick sources (session_flow.py _nego_view, role=interviewer).
// `recommendedForCandidate` reuses the existing B4 Recommendation model
// (HomeModels.swift) — dashboard_repo.recommendations() is the same shape.
struct PickSources: Codable, Equatable {
    let recommendedForCandidate: [Recommendation]
    let interviewerDoneSet: [NegotiatedCaseBrief]
    let libraryAllowed: Bool
}

// GET /api/practice/{id}/negotiation and the propose response
// (session_flow.py _nego_view). `whoseTurn` is null unless state=="negotiating".
// `pickSources` is present only for the interviewer's view.
struct NegotiationView: Codable, Equatable {
    let sessionId: Int
    let sessionState: String
    let yourRole: String
    let whoseTurn: String?
    let roundUsed: Int
    let currentPick: NegotiatedCaseBrief?
    let candidateCounter: NegotiatedCaseBrief?
    let candidateRequestedCase: RequestedCaseBrief?
    let pickSources: PickSources?
}

// MARK: - F5 Swap

// POST /api/practice/{id}/swap response (session_flow.py swap_initiate).
struct SwapInitiated: Codable, Equatable {
    let swapInviteId: Int
    let inviteeId: Int
}

// POST /api/practice/{id}/swap/accept response (session_flow.py swap_accept).
// `sessionId` is the NEW negotiating session created with reversed roles.
struct SwapAccepted: Codable, Equatable {
    let accepted: Bool
    let sessionId: Int
    let needsNegotiation: Bool
}

// MARK: - F5 Recap gate

// One row of GET /api/v1/recaps (session_flow.py list_recaps ->
// feedback_repo.list_unread_recaps): finalized-but-unclosed recaps where the
// caller was candidate. `finalizedAt`/`viewedAt` are ISO datetime strings kept
// as String (display-only; no Date parsing needed). NOTE: the backend docstring
// warns case_title can be NULL for legacy rows — matches the plan's String
// contract, but a legacy null would fail to decode.
struct RecapListItem: Codable, Equatable, Identifiable {
    let sessionId: Int
    let caseId: Int
    let caseTitle: String
    let interviewerName: String?
    let grade: Double?
    let finalizedAt: String?
    let viewedAt: String?

    var id: Int { sessionId }
}

// POST /api/practice/{id}/recap/close response (session_flow.py recap_close).
struct RecapCloseResult: Codable, Equatable {
    let closed: Bool
    let gateCleared: Bool
}

// POST /api/practice/{id}/recap/viewed response (session_flow.py recap_viewed).
struct RecapViewedResult: Codable, Equatable {
    let viewed: Bool
}

// MARK: - F5 Feedback report

// One scored rubric line of the released feedback (practice_feedback.py
// get_feedback). `id` is the template item id (a slug string, e.g. "structure").
struct FeedbackItem: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let dimension: String?
    let maxPoints: Int
    let points: Int
    let note: String
}

// One reveal-timeline entry (practice_feedback.py get_feedback ->
// reveals_repo.list_reveals: {exhibit_id, idx, revealed_at, t_offset_ms}).
// Decoded leniently — every field optional so a shape change never breaks the
// whole report decode.
struct FeedbackReveal: Codable, Equatable {
    let exhibitId: Int?
    let idx: Int?
    let revealedAt: String?
    let tOffsetMs: Int?
}

// GET /api/practice/{id}/feedback (practice_feedback.py get_feedback).
// `grade`/`finalizedAt` are null until finalize; kept as String for the date.
struct FeedbackReport: Codable, Equatable {
    let grade: Double?
    let finalizedAt: String?
    let notesMd: String
    let items: [FeedbackItem]
    let reveals: [FeedbackReveal]
    let caseId: Int?
    let caseTitle: String?
}

// MARK: - F5 Finalize debrief seeding

// finalize()'s prefill_proposal (practice_feedback.py post_finalize): seeds the
// candidate's next proposal back to the same interviewer.
struct FinalizePrefill: Codable, Equatable {
    let toUserId: Int
    let caseId: Int
}
