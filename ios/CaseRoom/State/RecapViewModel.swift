/*
 * Purpose: The recap REPORT page's presentation model (F5 Task 6) — fetches the
 *          released feedback report for a recap-gated session (feedbackReport),
 *          enriches the interviewer attribution from the unread-recap list
 *          (recaps), and marks the recap viewed on appear (recapViewed,
 *          candidate-only; a 409/403 is swallowed). All the pure, unit-testable
 *          rules (rubric-bar fill, paragraph split, item-note extraction,
 *          attribution/date/subline formatting) live in RecapPresentation so the
 *          View stays declarative.
 * Inputs: sessionId; a SessionFlowService (the fixture stub under the shot hatch,
 *         APIClient otherwise).
 * Outputs: RecapPresentation (pure), RecapViewModel (@Observable).
 * Run: owned by RecapReportView; onAppear() loads the report + marks viewed. The
 *      REQUIRED 1–5 close-out rating that clears the gate is T7's floating sheet
 *      (this page is read-only; the T7 seam is commented in RecapReportView).
 */

import Foundation
import Observation

// MARK: - Pure presentation rules (the genuinely testable bits)

enum RecapPresentation {
    /// A rubric bar's fill fraction (0…1) from an item's points / max_points.
    /// Clamped so a bad payload never overdraws or goes negative (shared shape
    /// with DebriefPresentation.barFraction — the recap report and the debrief
    /// draw the same bars, but each screen owns its own copy so neither depends
    /// on the other's file).
    static func barFraction(points: Int, max: Int) -> Double {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(Double(points) / Double(max), 0), 1)
    }

    /// Split notes_md prose into display paragraphs — blank-line separated
    /// (markdown paragraph breaks), trimmed, empties dropped. A single block with
    /// no blank lines stays one paragraph (soft wraps are NOT split).
    static func paragraphs(_ notesMd: String) -> [String] {
        notesMd
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Per-item feedback lines, in item order, keeping only the items whose note
    /// is non-empty (the "notes_md + item notes" half of the five serif
    /// paragraphs). Each pair is (dimension label, note prose).
    static func itemNotes(_ items: [FeedbackItem]) -> [(label: String, note: String)] {
        items.compactMap { item in
            let trimmed = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (item.label, trimmed)
        }
    }

    /// The interviewer attribution — their name, or a graceful fallback when the
    /// feedback report carries no author (the report endpoint has no name field;
    /// the name is enriched from the recap list, best-effort).
    static func attribution(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed! : "Your interviewer")
    }

    /// "WHAT T. BECKER WROTE" section kicker (canvas 6b).
    static func feedbackHeading(_ name: String?) -> String {
        "WHAT \(attribution(name).uppercased()) WROTE"
    }

    /// The report subline — "Feedback from {name}" plus the /5 rating when known
    /// (canvas 6b: "Feedback from T. Becker · …"). Data-driven from what the
    /// recap list carries; no invented "cased together N×" copy.
    static func subline(name: String?, grade: Double?) -> String {
        let base = "Feedback from \(attribution(name))"
        guard let grade else { return base }
        return "\(base) · rated \(String(format: "%.1f", grade)) / 5"
    }

    /// A short uppercase date kicker for the report header / masthead
    /// (finalized_at is an ISO-8601 string; nil-safe). e.g. "JUL 12, 2026".
    static func dateKicker(_ iso: String?) -> String? {
        guard let iso, let date = isoFormatter.date(from: iso) else { return nil }
        return displayFormatter.string(from: date).uppercased()
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

@Observable
@MainActor
final class RecapViewModel {
    let sessionId: Int
    private let flow: SessionFlowService

    /// The released feedback report (nil until loaded, or on a 409 before
    /// finalize — a real recap is always finalized, so nil here = load error).
    var report: FeedbackReport?
    /// The matching unread-recap row, enriched from recaps() — the source of the
    /// interviewer name + /5 rating the report endpoint doesn't carry. Optional:
    /// a failed/absent recaps() call leaves attribution on its graceful fallback.
    var recapItem: RecapListItem?
    /// True once a load attempt has completed (so the View can tell "loading"
    /// from "loaded, empty").
    var loaded = false
    /// True once recapViewed succeeded (marks the recap read; candidate-only).
    var viewedMarked = false

    init(sessionId: Int, flow: SessionFlowService) {
        self.sessionId = sessionId
        self.flow = flow
    }

    // MARK: - Derived (all pure via RecapPresentation)

    var interviewerName: String? { recapItem?.interviewerName }
    var caseTitle: String { report?.caseTitle ?? recapItem?.caseTitle ?? "Your case" }
    var items: [FeedbackItem] { report?.items ?? [] }
    var paragraphs: [String] { RecapPresentation.paragraphs(report?.notesMd ?? "") }
    var itemNotes: [(label: String, note: String)] { RecapPresentation.itemNotes(items) }
    // Grade: prefer the recap-list row, fall back to the report's own grade
    // (authoritative + always present post-finalize) so a recaps() miss never
    // drops the "· rated X / 5" — mirrors the caseTitle report→recap fallback.
    var subline: String { RecapPresentation.subline(name: interviewerName, grade: recapItem?.grade ?? report?.grade) }
    var dateKicker: String? { RecapPresentation.dateKicker(report?.finalizedAt) }
    var caseId: Int? { report?.caseId ?? recapItem?.caseId }

    // MARK: - Lifecycle

    /// Load the released report + enrich the attribution from the recap list.
    /// Both are best-effort (try?): the report is the page's content, the recap
    /// row only adds the author name / rating, so a failed recaps() never blocks
    /// the report from rendering.
    func loadReport() async {
        report = try? await flow.feedbackReport(id: sessionId)
        recapItem = (try? await flow.recaps())?.first { $0.sessionId == sessionId }
        loaded = true
    }

    /// Mark the recap viewed on appear (candidate-only; the server 409s a
    /// re-view / 403s the interviewer). Swallow every failure — viewing is a
    /// side-effect, never a gate on rendering the report.
    func markViewed() async {
        viewedMarked = ((try? await flow.recapViewed(id: sessionId)) != nil)
    }

    /// One-shot appear hook: render the report, then record the view.
    func onAppear() async {
        await loadReport()
        await markViewed()
    }
}
