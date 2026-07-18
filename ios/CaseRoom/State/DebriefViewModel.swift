/*
 * Purpose: The candidate debrief's presentation model (F5 Task 5) — fetches the
 *          released feedback report, drives the REQUIRED 1–5 rating that clears
 *          the recap gate (recapClose), and the interviewer's "Swap roles →
 *          invite sent" action. All the pure, unit-testable rules (bars from
 *          rubric items, rating-required gating, role-gated swap, avg readout)
 *          live in DebriefPresentation so the View stays declarative.
 * Inputs: sessionId; a SessionFlowService (the fixture stub under the shot
 *         hatch, APIClient otherwise).
 * Outputs: DebriefPresentation (pure), DebriefViewModel (@Observable).
 * Run: owned by DebriefView; loadReport() on appear (candidate), rate()/
 *      initiateSwap() from the debrief actions.
 */

import Foundation
import Observation

// MARK: - Pure presentation rules (the genuinely testable bits)

enum DebriefPresentation {
    /// A rubric bar's fill fraction (0…1) from an item's points / max_points.
    /// Clamped so a bad payload never overdraws or goes negative.
    static func barFraction(points: Int, max: Int) -> Double {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(Double(points) / Double(max), 0), 1)
    }

    /// The 1–5 rating gate: only a value in 1…5 is a valid close-out rating
    /// (server 422s otherwise). A tap of 0 / out-of-range must not close.
    static func isValidRating(_ n: Int) -> Bool { (1...5).contains(n) }

    /// Role gate for the swap action (DV-B3-SWAP: `/swap` is interviewer-only;
    /// a candidate/guest caller 403s). Only the interviewer debrief offers it.
    static func swapAvailable(role: String?) -> Bool { role == "interviewer" }

    /// The big average readout — the finalized grade to one decimal, or an
    /// em-dash before release.
    static func avgText(_ grade: Double?) -> String {
        guard let grade else { return "—" }
        return String(format: "%.1f", grade)
    }

    /// "AVG OF 4 DIMENSIONS" kicker (canvas 4a).
    static func dimensionsLabel(count: Int) -> String { "AVG OF \(count) DIMENSIONS" }

    /// Feedback is released once the report exists and carries a finalized grade
    /// (the server 409s the report before finalize, so a nil report = waiting).
    static func isReleased(_ report: FeedbackReport?) -> Bool {
        guard let report else { return false }
        return report.grade != nil || report.finalizedAt != nil
    }
}

@Observable
@MainActor
final class DebriefViewModel {
    let sessionId: Int
    private let flow: SessionFlowService

    /// The released feedback report (nil = waiting / 409 before finalize).
    var report: FeedbackReport?
    /// True once a load attempt has completed (so the View can tell "still
    /// loading" from "loaded, not yet released").
    var loaded = false

    /// The candidate's chosen 1–5 rating (0 = unrated).
    var rating = 0
    /// Set from recapClose's result — the gate is now clear for future entries.
    var gateCleared = false
    var rateError: String?

    /// The interviewer's swap invite state (canvas: "Swap roles" → "invite sent").
    var swapSent = false
    var swapError: String?

    init(sessionId: Int, flow: SessionFlowService) {
        self.sessionId = sessionId
        self.flow = flow
    }

    var released: Bool { DebriefPresentation.isReleased(report) }

    /// Candidate-only: fetch the released report. A 409 (before finalize) or any
    /// error leaves `report` nil → the View shows "waiting for feedback".
    func loadReport() async {
        report = try? await flow.feedbackReport(id: sessionId)
        loaded = true
    }

    /// The REQUIRED 1–5 close-out rating. A valid rating closes the recap
    /// (recapClose) and clears the gate; a failure rolls the selection back so
    /// the cells don't show a false confirmed state. Thumbs omitted — the
    /// candidate has none (interviewer-authored only, per B3).
    func rate(_ n: Int) async {
        guard DebriefPresentation.isValidRating(n) else { return }
        rateError = nil
        rating = n
        do {
            let result = try await flow.recapClose(id: sessionId, caseRating: n, thumbs: nil)
            gateCleared = result.gateCleared
        } catch {
            rating = 0
            rateError = "Couldn't save your rating. Try again."
        }
    }

    /// Interviewer-only: initiate a reversed-role rematch. On success the button
    /// becomes the verbatim "invite sent" confirmation.
    func initiateSwap() async {
        swapError = nil
        do {
            _ = try await flow.swap(id: sessionId)
            swapSent = true
        } catch {
            swapError = "Couldn't send the swap invite. Try again."
        }
    }
}
