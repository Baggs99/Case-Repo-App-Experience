/*
 * Purpose: Drives the Library tab — fetches the case catalog page, maps API
 *          rows to view-ready LibraryCase, and applies the retired-done
 *          type/done-toggle filters (open rows first, then a divider, then
 *          done rows) per F4 Design Decisions §0.4.
 * Inputs: LibraryService (default APIClient.shared); user-selected
 *         LibraryType/LibraryDone filters.
 * Outputs: none (in-memory state only).
 * Run: instantiated by CasesListView (Task 3); call load() from .task/.onChange.
 */

import Foundation
import Observation

// NEW protocol — coexists with the old CasesService. CasesViewModel.swift
// still backs CasesListView/CaseDetailView until Task 4 migrates them onto
// this protocol and deletes it (plan's "Plan-review round 1" resolution #4).
protocol LibraryService {
    func library(query: CaseQuery) async throws -> LibraryPage
    func caseDetail(id: Int) async throws -> CaseDetail
    func recentSessions() async throws -> [SessionSummary]
}

extension APIClient: LibraryService {
    func recentSessions() async throws -> [SessionSummary] {
        try await sessions(scope: "recent")
    }
}

// Type chips (canvas copy verbatim: All / Market entry / Profitability / M&A
// / Sizing). `.caseTypeFilter` is passed as CaseQuery.caseType; the server
// matches case_type by exact equality. ASSUMPTION: the live DB case_type
// column stores full title-case strings — pipeline/exporters/
// case_type_backfill.py confirms "Market Entry"/"Profitability"/"M&A" as
// canonical values, but no "Market Sizing" case_type was found anywhere in
// that backfill/enrichment table at the time of this task, so only
// "Profitability" (and, weakly, "Market Entry"/"M&A") are seed-confirmed —
// "Market Sizing" is a best guess. A spelling mismatch here doesn't crash;
// it just makes that chip's query return an empty filtered set server-side.
// Documented in the task report for the orchestrator/reviewer to verify
// against the live DB.
enum LibraryType: CaseIterable {
    case all, marketEntry, profitability, ma, sizing

    var label: String {
        switch self {
        case .all: return "All"
        case .marketEntry: return "Market entry"
        case .profitability: return "Profitability"
        case .ma: return "M&A"
        case .sizing: return "Sizing"
        }
    }

    var caseTypeFilter: String? {
        switch self {
        case .all: return nil
        case .marketEntry: return "Market Entry"
        case .profitability: return "Profitability"
        case .ma: return "M&A"
        case .sizing: return "Market Sizing"
        }
    }
}

enum LibraryDone: CaseIterable {
    case everything, notDone, done

    var label: String {
        switch self {
        case .everything: return "Everything"
        case .notDone: return "Not done"
        case .done: return "Done"
        }
    }
}

// View-ready row derived from CaseSummary. `meta` is the ROW meta ("D3");
// Task 4's detail screen appends the "rated by N candidates" suffix via
// `detailMeta` below rather than re-deriving it (Plan-review #1: that phrase
// is detail-only, never on the row).
struct LibraryCase: Identifiable, Equatable {
    let id: Int
    let ordinal: String
    let kicker: String
    let title: String
    let meta: String
    let done: Bool
    let avgRating: String
    let runCount: Int
    var recommended: Bool = false
    var scheduledNote: String? = nil
    var historyLine: String? = nil
    var historyScore: String? = nil
    let pdfLabel: String
    var previewUrls: [String] = []
    var pdfUrl: String? = nil

    var detailMeta: String { "\(meta) · rated by \(runCount) candidates" }

    static func from(_ summary: CaseSummary, ordinal: String) -> LibraryCase {
        var kickerParts: [String] = []
        if let caseType = summary.caseType, !caseType.isEmpty {
            kickerParts.append(caseType)
        }
        let schoolYear = [summary.sourceSchool, summary.sourceYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " ")
        if !schoolYear.isEmpty {
            kickerParts.append(schoolYear)
        }
        let kicker = kickerParts.joined(separator: " · ").uppercased()

        let meta: String
        if let score = summary.difficultyScore {
            meta = "D\(Int(score))"
        } else if let difficulty = summary.difficulty {
            meta = difficulty
        } else {
            meta = ""
        }

        let avgRatingText = summary.avgRating.map { String(format: "%g", $0) } ?? "—"
        let pdfLabel = summary.pageCount.map { "Case PDF — \($0) pages" } ?? "Case PDF"

        return LibraryCase(
            id: summary.id,
            ordinal: ordinal,
            kicker: kicker,
            title: summary.caseTitle,
            meta: meta,
            done: summary.doneForYou ?? false,
            avgRating: avgRatingText,
            runCount: summary.runCount ?? 0,
            pdfLabel: pdfLabel
        )
    }
}

enum LibraryRow: Equatable, Identifiable {
    case row(LibraryCase)
    case divider(String)

    var id: String {
        switch self {
        case .row(let libraryCase): return "row-\(libraryCase.id)"
        case .divider(let label): return "divider-\(label)"
        }
    }
}

@Observable
final class LibraryViewModel {
    var type: LibraryType = .all
    var done: LibraryDone = .everything
    var page: LibraryPage?
    // Full loaded list — ordinals assigned ONCE here (descending index over
    // the load() response), so they stay stable across done-toggle changes
    // (which only re-filter this array, never reload it).
    var allCases: [LibraryCase] = []
    var selectedID: Int?
    var isLoading = false
    var errorMessage: String?

    private let service: LibraryService

    init(service: LibraryService = APIClient.shared) {
        self.service = service
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let query = CaseQuery(caseType: type.caseTypeFilter, limit: 200)
            let fetchedPage = try await service.library(query: query)
            let total = fetchedPage.cases.count
            allCases = fetchedPage.cases.enumerated().map { index, summary in
                LibraryCase.from(summary, ordinal: String(format: "%02d", total - index))
            }
            page = fetchedPage
        } catch {
            allCases = []
            page = nil
            errorMessage = "Couldn't load the library. Try again."
        }
    }

    // Splits allCases into the open/done groups the current `done` toggle
    // shows. Shared by filteredRows and countLine so both agree.
    private var shownGroups: (open: [LibraryCase], done: [LibraryCase]) {
        let openCases = allCases.filter { !$0.done }
        let doneCases = allCases.filter { $0.done }
        switch done {
        case .everything: return (openCases, doneCases)
        case .notDone: return (openCases, [])
        case .done: return ([], doneCases)
        }
    }

    // The type chip is already applied server-side via the load() query, so
    // allCases already reflects it — only the done toggle is applied here.
    var filteredRows: [LibraryRow] {
        let (shownOpen, shownDone) = shownGroups
        var rows: [LibraryRow] = shownOpen.map { .row($0) }
        if !shownOpen.isEmpty && !shownDone.isEmpty {
            rows.append(.divider("DONE — YOURS TO INTERVIEW WITH"))
        }
        rows += shownDone.map { .row($0) }
        return rows
    }

    // Client-filtered count (Plan-review #2): reflects the CURRENT
    // type+done-filtered set, not the page's server-side open_count/done_count.
    var countLine: String {
        let (shownOpen, shownDone) = shownGroups
        return "\(shownOpen.count) OPEN · \(shownDone.count) DONE"
    }

    // Tablet fallback: selected id if present in the loaded set, else the
    // first row currently shown.
    var selectedCase: LibraryCase? {
        if let selectedID, let match = allCases.first(where: { $0.id == selectedID }) {
            return match
        }
        for row in filteredRows {
            if case .row(let libraryCase) = row { return libraryCase }
        }
        return nil
    }

    var isEmpty: Bool { filteredRows.isEmpty }
}
