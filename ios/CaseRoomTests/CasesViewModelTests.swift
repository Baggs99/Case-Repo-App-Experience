/*
 * Purpose: Unit tests for CasesViewModel — stubbed CasesService proving
 *          search/filter query-building and result/error state handling.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubCasesService: CasesService {
    var casesResult: Result<[CaseSummary], Error> = .success([])
    var recordedQueries: [CaseQuery] = []

    func cases(query: CaseQuery) async throws -> [CaseSummary] {
        recordedQueries.append(query)
        return try casesResult.get()
    }

    func caseDetail(id: Int) async throws -> CaseDetail {
        fatalError("not exercised by these tests")
    }
}

final class CasesViewModelTests: XCTestCase {
    private func makeCase(id: Int, title: String) -> CaseSummary {
        CaseSummary(
            id: id, caseTitle: title, caseType: nil, difficulty: "Medium",
            difficultyScore: nil, firm: nil, industry: nil, industryDisplay: nil,
            industryRaw: nil, pageCount: nil, sourceSchool: nil, sourceYear: nil,
            avgRating: nil, runCount: nil, doneForYou: nil
        )
    }

    func testLoadWithQueryTextCallsServiceAndPopulatesResults() async {
        let stub = StubCasesService()
        let expected = [makeCase(id: 1, title: "Widget Co Market Sizing")]
        stub.casesResult = .success(expected)
        let viewModel = CasesViewModel(service: stub)
        viewModel.query = "market"

        await viewModel.load()

        XCTAssertEqual(viewModel.results, expected)
        XCTAssertEqual(stub.recordedQueries.last?.q, "market")
    }

    func testSettingDifficultyPassesItThroughToTheService() async {
        let stub = StubCasesService()
        stub.casesResult = .success([makeCase(id: 2, title: "Beta Corp")])
        let viewModel = CasesViewModel(service: stub)
        viewModel.difficulty = "Hard"

        await viewModel.load()

        XCTAssertEqual(stub.recordedQueries.last?.difficulty, "Hard")
    }

    func testServiceErrorLeavesResultsEmptyAndSetsErrorState() async {
        let stub = StubCasesService()
        stub.casesResult = .failure(APIError.server(500))
        let viewModel = CasesViewModel(service: stub)
        viewModel.results = [makeCase(id: 3, title: "Stale Result")]

        await viewModel.load()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
