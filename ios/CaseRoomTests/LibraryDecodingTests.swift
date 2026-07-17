/*
 * Purpose: Unit tests for F4 Task 1 — case aggregates (avg_rating/run_count/
 *          done_for_you) + LibraryPage decoding on the /api/v1/cases* API,
 *          per the B3 contract (docs/superpowers/sdd/bgap-b3-report.md).
 * Inputs: canned JSON strings, stubbed via StubURLProtocol (shared with
 *         APIClientTests.swift) so the real APIClient.library/caseDetail
 *         request+decode pipeline is exercised, not a private mirror.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class LibraryDecodingTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let session = URLSession(configuration: StubURLProtocol.sessionConfiguration)
        client = APIClient(session: session)
    }

    private func stubJSON(_ json: String, status: Int = 200) {
        StubURLProtocol.stubs.append(
            .init(statusCode: status, data: Data(json.utf8), headers: ["Content-Type": "application/json"])
        )
    }

    // MARK: - library(query:) — with aggregates

    func testLibraryRequestAndDecode_WithAggregates() async throws {
        stubJSON(#"""
        {"cases": [{"id": 5, "case_title": "Widget Co", "case_type": "Profitability",
          "difficulty": "Medium", "difficulty_score": 5.5, "firm": "Widget Co",
          "industry": "Technology", "industry_display": "Tech", "industry_raw": "tech",
          "page_count": 10, "source_school": "Yale", "source_year": 2024,
          "avg_rating": 4.2, "run_count": 12, "done_for_you": true}],
         "total": 1, "open_count": 3, "done_count": 2}
        """#)

        let page = try await client.library(query: CaseQuery())

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.openCount, 3)
        XCTAssertEqual(page.doneCount, 2)
        XCTAssertEqual(page.cases.count, 1)
        XCTAssertEqual(page.cases[0].avgRating, 4.2)
        XCTAssertEqual(page.cases[0].runCount, 12)
        XCTAssertEqual(page.cases[0].doneForYou, true)
    }

    // MARK: - library(query:) — back-compat, aggregate keys missing

    func testLibraryRequestAndDecode_MissingAggregateKeysStillDecodesNil() async throws {
        stubJSON(#"""
        {"cases": [{"id": 6, "case_title": "Beta Corp"}],
         "total": 1, "open_count": 1, "done_count": 0}
        """#)

        let page = try await client.library(query: CaseQuery())

        XCTAssertEqual(page.openCount, 1)
        XCTAssertEqual(page.doneCount, 0)
        XCTAssertEqual(page.cases.count, 1)
        XCTAssertNil(page.cases[0].avgRating)
        XCTAssertNil(page.cases[0].runCount)
        XCTAssertNil(page.cases[0].doneForYou)
    }

    // MARK: - library(query:) — query items match cases(query:)

    func testLibraryRequestBuildsSameQueryItemsAsCases() async throws {
        stubJSON(#"{"cases": [], "total": 0, "open_count": 0, "done_count": 0}"#)

        _ = try await client.library(query: CaseQuery(q: "market", caseType: "Sizing", limit: 200))

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/cases")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains(URLQueryItem(name: "q", value: "market")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "case_type", value: "Sizing")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "200")))
    }

    // MARK: - caseDetail(id:) — aggregates + previewUrls/pdfUrl

    func testCaseDetailRequestAndDecode_WithAggregates() async throws {
        stubJSON(#"""
        {"id": 7, "case_title": "Gamma LLC", "case_type": "M&A", "difficulty": "Hard",
         "difficulty_score": 7.0, "firm": "Gamma LLC", "industry": "Finance",
         "industry_display": "Finance", "industry_raw": "finance", "page_count": 15,
         "source_school": "Harvard", "source_year": 2023,
         "preview_urls": ["/files/cases/7/preview/1", "/files/cases/7/preview/2"],
         "pdf_url": "/files/cases/7/pdf",
         "avg_rating": 3.8, "run_count": 5, "done_for_you": false}
        """#)

        let detail = try await client.caseDetail(id: 7)

        XCTAssertEqual(detail.id, 7)
        XCTAssertEqual(detail.avgRating, 3.8)
        XCTAssertEqual(detail.runCount, 5)
        XCTAssertEqual(detail.doneForYou, false)
        XCTAssertEqual(detail.previewUrls, ["/files/cases/7/preview/1", "/files/cases/7/preview/2"])
        XCTAssertEqual(detail.pdfUrl, "/files/cases/7/pdf")
    }

    // MARK: - caseDetail(id:) — back-compat, aggregate keys missing

    func testCaseDetailRequestAndDecode_MissingAggregateKeysStillDecodesNil() async throws {
        stubJSON(#"""
        {"id": 8, "case_title": "Delta Inc", "preview_urls": [], "pdf_url": "/files/cases/8/pdf"}
        """#)

        let detail = try await client.caseDetail(id: 8)

        XCTAssertNil(detail.avgRating)
        XCTAssertNil(detail.runCount)
        XCTAssertNil(detail.doneForYou)
    }
}
