/*
 * Purpose: DEBUG-only fixture data for Library screenshots (F4 Tasks 3-5) — the
 *          Design Decisions §3/§7 canonical 8 cases (tablet `CASES` array,
 *          July-17 snapshot) plus a stub LibraryService so `-LibraryFixtures`
 *          screenshots need no dev server. Decisions §7 "Fixture day-state":
 *          the phone canvas's own case array lives in a truncated 1-series
 *          tail and is unavailable, so BOTH phone and tablet screenshots reuse
 *          the tablet July-17 snapshot — a documented, screenshot-only
 *          deviation from the phone canvas's July-16 day; never shipped.
 * Inputs: none.
 * Outputs: LibraryFixtures (cases/decorations/sessions), FixtureLibraryService.
 * Run: CasesListView reads -LibraryFixtures and binds LibraryViewModel to
 *      LibraryFixtures.service; CaseRoomApp.applyDebugLaunchHatches fakes auth
 *      for the same arg.
 */

#if DEBUG
import Foundation

enum LibraryFixtures {

    /// The service CasesListView binds to under `-LibraryFixtures`.
    static let service = FixtureLibraryService()

    // Design Decisions §7 tablet `CASES` array, id 08 (ev) -> 01 (freight),
    // newest/highest ordinal first — LibraryViewModel.load() assigns ordinals
    // from array position, so this order reproduces the canvas's 08..01.
    // difficulty word omitted (score-only per row meta derivation); the
    // canvas's own "~25 min" duration isn't in the live API shape either
    // (Task 2 seam) so it's intentionally absent here too.
    static let cases: [CaseSummary] = [
        CaseSummary(id: 8, caseTitle: "EV charging — size the German market",
                    caseType: "Market Sizing", difficulty: nil, difficultyScore: 3,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 6, sourceSchool: "Stern", sourceYear: 2024,
                    avgRating: 4.6, runCount: 128, doneForYou: false),
        CaseSummary(id: 7, caseTitle: "Low-cost carrier enters the Nordic market",
                    caseType: "Market Entry", difficulty: nil, difficultyScore: 4,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 8, sourceSchool: "Kellogg", sourceYear: 2019,
                    avgRating: 4.7, runCount: 214, doneForYou: true),
        CaseSummary(id: 6, caseTitle: "Ski resort: revenue up, profit down",
                    caseType: "Profitability", difficulty: nil, difficultyScore: 3,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 7, sourceSchool: "Booth", sourceYear: 2022,
                    avgRating: 4.4, runCount: 187, doneForYou: true),
        CaseSummary(id: 5, caseTitle: "US grocer weighs a move into meal kits",
                    caseType: "Market Entry", difficulty: nil, difficultyScore: 2,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 5, sourceSchool: "Kellogg", sourceYear: 2019,
                    avgRating: 4.2, runCount: 156, doneForYou: true),
        CaseSummary(id: 4, caseTitle: "Private equity eyes a dental roll-up",
                    caseType: "M&A", difficulty: nil, difficultyScore: 4,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 8, sourceSchool: "Wharton", sourceYear: 2023,
                    avgRating: 4.5, runCount: 98, doneForYou: false),
        CaseSummary(id: 3, caseTitle: "Regional bank merger: the synergies",
                    caseType: "M&A", difficulty: nil, difficultyScore: 3,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 6, sourceSchool: "INSEAD", sourceYear: 2021,
                    avgRating: 4.1, runCount: 143, doneForYou: true),
        CaseSummary(id: 2, caseTitle: "Airport lounges — size the European market",
                    caseType: "Market Sizing", difficulty: nil, difficultyScore: 2,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 4, sourceSchool: "LBS", sourceYear: 2023,
                    avgRating: 4.3, runCount: 112, doneForYou: false),
        CaseSummary(id: 1, caseTitle: "Freight carrier: fuel costs eat the margin",
                    caseType: "Profitability", difficulty: nil, difficultyScore: 3,
                    firm: nil, industry: nil, industryDisplay: nil, industryRaw: nil,
                    pageCount: 6, sourceSchool: "Booth", sourceYear: 2020,
                    avgRating: 4.0, runCount: 132, doneForYou: false),
    ]

    // id -> (recommended, scheduledNote). EV charging (id 8) is the canvas's
    // RECS[0] recommendation ("FOR YOU"); dental (id 4) carries the §7
    // schedule ("dental.sched = 'Today 18:00 · T. Becker'"), trimmed to the
    // row-tag copy the task brief calls for ("SCHEDULED" label + this note).
    static let decorations: [Int: (recommended: Bool, scheduledNote: String?)] = [
        8: (true, nil),
        4: (false, "Today 18:00"),
    ]

    /// §3/§7 recap/history rows for Task 4's "YOUR HISTORY WITH IT" — title-
    /// matched against `cases` by LibraryViewModel/CaseDetailView since
    /// SessionSummary carries no case_id (documented seam, plan resolution #6).
    static let sessions: [SessionSummary] = [
        SessionSummary(id: 101, role: "candidate", otherUser: "M. Lindqvist",
                        caseTitle: "Low-cost carrier enters the Nordic market",
                        scheduledAt: nil, state: "done", endedAt: date("2026-07-16"), grade: 7.2),
        SessionSummary(id: 102, role: "candidate", otherUser: "T. Becker",
                        caseTitle: "Ski resort: revenue up, profit down",
                        scheduledAt: nil, state: "done", endedAt: date("2026-07-12"), grade: 4.1),
        SessionSummary(id: 103, role: "candidate", otherUser: "S. Park",
                        caseTitle: "US grocer weighs a move into meal kits",
                        scheduledAt: nil, state: "done", endedAt: date("2026-07-08"), grade: 4.5),
        SessionSummary(id: 104, role: "candidate", otherUser: "guest",
                        caseTitle: "Regional bank merger: the synergies",
                        scheduledAt: nil, state: "done", endedAt: date("2026-06-30"), grade: 3.8),
    ]

    private static func date(_ yyyyMMdd: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: yyyyMMdd) ?? Date()
    }
}

/// Stub LibraryService seeded with LibraryFixtures — no network. The type
/// chip filter is applied here (mirrors the live server's exact-equality
/// case_type match) so `-LibraryFixtures` screenshots exercise real filtering.
final class FixtureLibraryService: LibraryService {
    func library(query: CaseQuery) async throws -> LibraryPage {
        let filtered = LibraryFixtures.cases.filter { summary in
            guard let caseType = query.caseType else { return true }
            return summary.caseType == caseType
        }
        let open = filtered.filter { !($0.doneForYou ?? false) }.count
        let done = filtered.filter { $0.doneForYou ?? false }.count
        return LibraryPage(cases: filtered, total: filtered.count, openCount: open, doneCount: done)
    }

    func caseDetail(id: Int) async throws -> CaseDetail {
        guard let summary = LibraryFixtures.cases.first(where: { $0.id == id }) else {
            throw APIError.server(404)
        }
        return CaseDetail(
            id: summary.id, caseTitle: summary.caseTitle, caseType: summary.caseType,
            difficulty: summary.difficulty, difficultyScore: summary.difficultyScore,
            firm: summary.firm, industry: summary.industry, industryDisplay: summary.industryDisplay,
            industryRaw: summary.industryRaw, pageCount: summary.pageCount,
            sourceSchool: summary.sourceSchool, sourceYear: summary.sourceYear,
            previewUrls: [], pdfUrl: "/fixtures/case-\(summary.id).pdf",
            avgRating: summary.avgRating, runCount: summary.runCount, doneForYou: summary.doneForYou
        )
    }

    func recentSessions() async throws -> [SessionSummary] {
        LibraryFixtures.sessions
    }
}
#endif
