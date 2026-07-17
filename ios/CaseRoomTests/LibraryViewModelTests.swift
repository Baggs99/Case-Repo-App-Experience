/*
 * Purpose: Unit tests for LibraryViewModel — stubbed LibraryService proving
 *          the retired-done partition (open/divider/done), the client-side
 *          countLine, type-filter query building, and CaseSummary ->
 *          LibraryCase field derivation (kicker/meta/ordinal/avgRating/pdfLabel).
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubLibraryService: LibraryService {
    var libraryResult: Result<LibraryPage, Error> = .success(LibraryPage(cases: [], total: 0, openCount: 0, doneCount: 0))
    var caseDetailResult: Result<CaseDetail, Error>?
    var recentSessionsResult: Result<[SessionSummary], Error> = .success([])
    var recordedQueries: [CaseQuery] = []

    func library(query: CaseQuery) async throws -> LibraryPage {
        recordedQueries.append(query)
        return try libraryResult.get()
    }

    func caseDetail(id: Int) async throws -> CaseDetail {
        guard let caseDetailResult else { fatalError("not exercised by these tests") }
        return try caseDetailResult.get()
    }

    func recentSessions() async throws -> [SessionSummary] {
        try recentSessionsResult.get()
    }
}

final class LibraryViewModelTests: XCTestCase {
    // Builds a CaseSummary with sensible defaults; override only what a test cares about.
    private func makeSummary(
        id: Int,
        title: String = "Widget Co",
        caseType: String? = "Profitability",
        difficulty: String? = "Medium",
        difficultyScore: Double? = 3.0,
        sourceSchool: String? = "Yale",
        sourceYear: Int? = 2024,
        pageCount: Int? = 6,
        avgRating: Double? = 4.7,
        runCount: Int? = 9,
        doneForYou: Bool? = false
    ) -> CaseSummary {
        CaseSummary(
            id: id, caseTitle: title, caseType: caseType, difficulty: difficulty,
            difficultyScore: difficultyScore, firm: nil, industry: nil, industryDisplay: nil,
            industryRaw: nil, pageCount: pageCount, sourceSchool: sourceSchool, sourceYear: sourceYear,
            avgRating: avgRating, runCount: runCount, doneForYou: doneForYou
        )
    }

    private func makePage(_ summaries: [CaseSummary]) -> LibraryPage {
        let open = summaries.filter { !($0.doneForYou ?? false) }.count
        let done = summaries.filter { $0.doneForYou ?? false }.count
        return LibraryPage(cases: summaries, total: summaries.count, openCount: open, doneCount: done)
    }

    // MARK: - Partitioning + divider

    func testEverythingShowsOpenThenDividerThenDone() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
            makeSummary(id: 3, doneForYou: false),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        let rows = vm.filteredRows
        XCTAssertEqual(rows.count, 4) // 2 open + 1 divider + 1 done
        guard case .row(let first) = rows[0], case .row(let second) = rows[1],
              case .divider(let label) = rows[2], case .row(let last) = rows[3] else {
            return XCTFail("unexpected row shape: \(rows)")
        }
        XCTAssertFalse(first.done)
        XCTAssertFalse(second.done)
        XCTAssertEqual(label, "DONE — YOURS TO INTERVIEW WITH")
        XCTAssertTrue(last.done)
    }

    func testNotDoneShowsOnlyOpenRowsNoDivider() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .notDone

        await vm.load()

        let rows = vm.filteredRows
        XCTAssertEqual(rows.count, 1)
        guard case .row(let only) = rows[0] else { return XCTFail("expected a row") }
        XCTAssertFalse(only.done)
        XCTAssertFalse(rows.contains { if case .divider = $0 { return true }; return false })
    }

    func testDoneShowsOnlyDoneRowsNoDivider() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .done

        await vm.load()

        let rows = vm.filteredRows
        XCTAssertEqual(rows.count, 1)
        guard case .row(let only) = rows[0] else { return XCTFail("expected a row") }
        XCTAssertTrue(only.done)
        XCTAssertFalse(rows.contains { if case .divider = $0 { return true }; return false })
    }

    func testDividerAbsentWhenAllOpenUnderEverything() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: false),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        let rows = vm.filteredRows
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows.contains { if case .divider = $0 { return true }; return false })
    }

    func testDividerAbsentWhenAllDoneUnderEverything() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: true),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        let rows = vm.filteredRows
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows.contains { if case .divider = $0 { return true }; return false })
    }

    // MARK: - countLine

    func testCountLineUnderEverythingReflectsBothGroups() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
            makeSummary(id: 3, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        XCTAssertEqual(vm.countLine, "1 OPEN · 2 DONE")
    }

    func testCountLineUnderDoneShowsZeroOpen() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
            makeSummary(id: 3, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .done

        await vm.load()

        XCTAssertEqual(vm.countLine, "0 OPEN · 2 DONE")
    }

    func testCountLineUnderNotDoneShowsZeroDone() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .notDone

        await vm.load()

        XCTAssertEqual(vm.countLine, "1 OPEN · 0 DONE")
    }

    // MARK: - Type filter -> query

    func testTypeCaseTypeFilterPassesDBSpellingIntoQuery() async {
        let stub = StubLibraryService()
        let vm = LibraryViewModel(service: stub)

        vm.type = .profitability
        await vm.load()
        XCTAssertEqual(stub.recordedQueries.last?.caseType, "Profitability")

        vm.type = .marketEntry
        await vm.load()
        XCTAssertEqual(stub.recordedQueries.last?.caseType, "Market Entry")

        vm.type = .ma
        await vm.load()
        XCTAssertEqual(stub.recordedQueries.last?.caseType, "M&A")

        vm.type = .sizing
        await vm.load()
        XCTAssertEqual(stub.recordedQueries.last?.caseType, "Market Sizing")

        vm.type = .all
        await vm.load()
        XCTAssertNil(stub.recordedQueries.last?.caseType)
    }

    func testLoadRequestsLimit200() async {
        let stub = StubLibraryService()
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(stub.recordedQueries.last?.limit, 200)
    }

    // MARK: - Field derivation

    func testFieldDerivationFromCaseSummary() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(
                id: 42, title: "Widget Co Profitability Drop", caseType: "Profitability",
                difficulty: "Medium", difficultyScore: 3.0, sourceSchool: "Yale", sourceYear: 2024,
                pageCount: 6, avgRating: 4.7, runCount: 9, doneForYou: false
            ),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        let libraryCase = try? XCTUnwrap(vm.allCases.first)
        XCTAssertEqual(libraryCase?.kicker, "PROFITABILITY · YALE 2024")
        XCTAssertEqual(libraryCase?.meta, "D3")
        XCTAssertEqual(libraryCase?.avgRating, "4.7")
        XCTAssertEqual(libraryCase?.pdfLabel, "Case PDF — 6 pages")
        XCTAssertEqual(libraryCase?.detailMeta, "D3 · rated by 9 candidates")
    }

    func testAvgRatingDashWhenNil() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, avgRating: nil, runCount: nil),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(vm.allCases.first?.avgRating, "—")
        XCTAssertEqual(vm.allCases.first?.runCount, 0)
    }

    // Carry-in from Task 2 review: %g dropped the trailing zero ("4" not
    // "4.0"), breaking canvas tabular fidelity — a whole-number rating must
    // still render one decimal place.
    func testAvgRatingRendersOneDecimalForWholeNumbers() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, avgRating: 4.0),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(vm.allCases.first?.avgRating, "4.0")
    }

    func testPdfLabelFallsBackWhenPageCountNil() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, pageCount: nil),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(vm.allCases.first?.pdfLabel, "Case PDF")
    }

    func testMetaFallsBackToDifficultyWordWhenScoreNil() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, difficulty: "Hard", difficultyScore: nil),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(vm.allCases.first?.meta, "Hard")
    }

    // MARK: - Ordinals

    func testOrdinalsAssignedDescendingAndStableAcrossToggleChange() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
            makeSummary(id: 3, doneForYou: false),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        XCTAssertEqual(vm.allCases.map(\.ordinal), ["03", "02", "01"])
        let ordinalBefore = vm.allCases.first { $0.id == 2 }?.ordinal

        vm.done = .done // re-filter only, no reload

        let ordinalAfter = vm.allCases.first { $0.id == 2 }?.ordinal
        XCTAssertEqual(ordinalBefore, ordinalAfter)
        XCTAssertEqual(ordinalAfter, "02")
    }

    // MARK: - Empty state

    func testEmptyWhenNoCasesMatchFilter() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertTrue(vm.isEmpty)
        XCTAssertTrue(vm.filteredRows.isEmpty)
    }

    // MARK: - Selection fallback

    func testSelectedCaseFallsBackToFirstFilteredRowWhenNoSelection() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertEqual(vm.selectedCase?.id, 1)

        vm.selectedID = 2
        XCTAssertEqual(vm.selectedCase?.id, 2)
    }

    // MARK: - No population-count phrasing leaks into any string

    func testNoPopulationCountPhrasingInAnyProducedString() async {
        let stub = StubLibraryService()
        stub.libraryResult = .success(makePage([
            makeSummary(id: 1, doneForYou: false),
            makeSummary(id: 2, doneForYou: true),
        ]))
        let vm = LibraryViewModel(service: stub)
        vm.done = .everything

        await vm.load()

        var strings: [String] = [vm.countLine]
        for row in vm.filteredRows {
            switch row {
            case .row(let libraryCase):
                strings.append(contentsOf: [
                    libraryCase.kicker, libraryCase.title, libraryCase.meta,
                    libraryCase.avgRating, libraryCase.pdfLabel, libraryCase.detailMeta,
                ])
            case .divider(let label):
                strings.append(label)
            }
        }
        for string in strings {
            XCTAssertFalse(string.contains("of "), "unexpected population-count phrasing in: \(string)")
        }
    }

    // MARK: - Error handling

    func testServiceErrorClearsCasesAndSetsErrorMessage() async {
        let stub = StubLibraryService()
        stub.libraryResult = .failure(APIError.server(500))
        let vm = LibraryViewModel(service: stub)

        await vm.load()

        XCTAssertTrue(vm.allCases.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }
}
