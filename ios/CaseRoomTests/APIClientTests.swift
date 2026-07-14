/*
 * Purpose: Unit tests for APIClient — URLProtocol-stubbed request/response
 *          assertions plus real-fixture decode tests against captured
 *          backend JSON (proving the date-decoding strategy on live data).
 * Inputs: canned JSON strings; JSON fixtures under ios/CaseRoomTests/Fixtures.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

// MARK: - Stub URLProtocol

final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
        let headers: [String: String]
    }

    static var stubs: [Stub] = []
    static var recordedRequests: [URLRequest] = []

    static func reset() {
        stubs = []
        recordedRequests = []
    }

    static var sessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.recordedRequests.append(request)
        guard !StubURLProtocol.stubs.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = StubURLProtocol.stubs.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
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

    // MARK: - login

    func testLoginRequestAndDecode() async throws {
        stubJSON(#"{"user": {"id": 1, "email": "a@yale.edu", "name": "Alice Dev"}}"#)

        let user = try await client.login(email: "a@yale.edu", password: "caseroom-dev-1")

        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.email, "a@yale.edu")
        XCTAssertEqual(user.name, "Alice Dev")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/auth/login")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["email"] as? String, "a@yale.edu")
        XCTAssertEqual(body["password"] as? String, "caseroom-dev-1")
    }

    func testLoginUnauthorized() async {
        stubJSON(#"{"detail": "invalid_credentials"}"#, status: 401)

        do {
            _ = try await client.login(email: "a@yale.edu", password: "wrong")
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("expected APIError.unauthorized, got \(error)")
        }
    }

    // MARK: - cases

    func testCasesRequestAndDecode() async throws {
        stubJSON(#"""
        {"cases": [{"id": 5, "case_title": "Widget Co", "case_type": "Profitability",
          "difficulty": "Medium", "difficulty_score": 5.5, "firm": "Widget Co",
          "industry": "Technology", "industry_display": "Tech", "industry_raw": "tech",
          "page_count": 10, "source_school": "Yale", "source_year": 2024}], "total": 1}
        """#)

        let cases = try await client.cases(query: CaseQuery(limit: 3))

        XCTAssertEqual(cases.count, 1)
        XCTAssertEqual(cases[0].id, 5)
        XCTAssertEqual(cases[0].caseTitle, "Widget Co")
        XCTAssertEqual(cases[0].difficultyScore, 5.5)
        XCTAssertEqual(cases[0].sourceSchool, "Yale")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/cases")
        XCTAssertEqual(request.httpMethod, "GET")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "3")))
    }

    // MARK: - proposals

    func testProposalsRequestAndDecode() async throws {
        stubJSON(#"""
        {"proposals": [{"id": 9, "from_name": "Bob Dev", "from_role": "interviewer",
          "case_id": 5, "case_title": "Widget Co", "case_type": "Profitability",
          "difficulty": "Medium", "message": "Let's practice",
          "proposed_times": ["2026-07-20T14:30:00.123456+00:00"],
          "created_at": "2026-07-14T10:00:00+00:00"}]}
        """#)

        let proposals = try await client.proposals()

        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0].fromName, "Bob Dev")
        XCTAssertEqual(proposals[0].proposedTimes.count, 1)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/proposals")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - dashboard

    func testDashboardRequestAndDecode() async throws {
        stubJSON(#"""
        {"sessions_finalized": 4, "streak_weeks": 2, "next_session": {
          "id": 3, "role": "candidate", "other_user": "Bob Dev",
          "case_title": "Widget Co", "scheduled_at": "2026-07-20T14:30:00+00:00",
          "state": "scheduled", "ended_at": null, "grade": null}}
        """#)

        let stats = try await client.dashboard()

        XCTAssertEqual(stats.sessionsFinalized, 4)
        XCTAssertEqual(stats.streakWeeks, 2)
        XCTAssertEqual(stats.nextSession?.otherUser, "Bob Dev")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/dashboard")
    }

    // MARK: - sessions

    func testSessionsRequestAndDecode() async throws {
        stubJSON(#"""
        {"sessions": [{"id": 1, "role": "interviewer", "other_user": "Bob Dev",
          "case_title": "Widget Co", "scheduled_at": null, "state": null,
          "ended_at": "2026-07-10T09:00:00+00:00", "grade": 87.5}]}
        """#)

        let sessions = try await client.sessions(scope: "recent")

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].grade, 87.5)
        XCTAssertNotNil(sessions[0].endedAt)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/sessions")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "scope", value: "recent")))
    }

    // MARK: - 401 mapping generally

    func testMeUnauthorizedMapsToAPIErrorUnauthorized() async {
        stubJSON(#"{"detail": "not_authenticated"}"#, status: 401)

        do {
            _ = try await client.me()
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("expected APIError.unauthorized, got \(error)")
        }
    }

    // MARK: - resolveURL

    func testResolveURLRelativePathResolvesAgainstBaseURL() {
        let resolved = client.resolveURL("/files/cases/5/preview/1?v=abc")

        XCTAssertEqual(resolved?.absoluteString, "\(client.baseURL.absoluteString)/files/cases/5/preview/1?v=abc")
    }

    func testResolveURLAbsoluteCDNURLPassesThroughUnchanged() {
        let absolute = "https://cdn.example.com/previews/foo/1.jpg"

        let resolved = client.resolveURL(absolute)

        XCTAssertEqual(resolved?.absoluteString, absolute)
    }

    func testResolveURLPathWithoutLeadingSlashStillResolvesAgainstBaseURLHost() {
        // RFC 3986 §5.3 merge: base has a defined authority and an empty path,
        // so the relative path is prefixed with "/" before merging — same
        // result as the leading-slash case above.
        let resolved = client.resolveURL("files/cases/5/preview/1")

        XCTAssertEqual(resolved?.absoluteString, "\(client.baseURL.absoluteString)/files/cases/5/preview/1")
    }

    // MARK: - Real-fixture decode tests

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).json not bundled")
        }
        return try Data(contentsOf: url)
    }

    private func fixtureDecoder() -> JSONDecoder {
        // Mirrors APIClient's private decoder configuration exactly.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) { return date }
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date \(string)")
        }
        return decoder
    }

    func testRealFixture_me() throws {
        let data = try loadFixture("me")
        let user = try fixtureDecoder().decode(User.self, from: data)
        XCTAssertGreaterThan(user.id, 0)
        XCTAssertFalse(user.email.isEmpty)
    }

    func testRealFixture_cases() throws {
        struct CasesResponse: Decodable { let cases: [CaseSummary]; let total: Int }
        let data = try loadFixture("cases")
        let response = try fixtureDecoder().decode(CasesResponse.self, from: data)
        XCTAssertFalse(response.cases.isEmpty)
        XCTAssertFalse(response.cases[0].caseTitle.isEmpty)
    }

    func testRealFixture_caseDetail() throws {
        let data = try loadFixture("case_detail")
        let detail = try fixtureDecoder().decode(CaseDetail.self, from: data)
        XCTAssertFalse(detail.pdfUrl.isEmpty)
    }

    func testRealFixture_proposals() throws {
        struct ProposalsResponse: Decodable { let proposals: [Proposal] }
        let data = try loadFixture("proposals")
        let response = try fixtureDecoder().decode(ProposalsResponse.self, from: data)
        if let first = response.proposals.first {
            XCTAssertGreaterThan(first.createdAt.timeIntervalSince1970, 0)
        }
    }

    func testRealFixture_sessionsUpcoming() throws {
        struct SessionsResponse: Decodable { let sessions: [SessionSummary] }
        let data = try loadFixture("sessions_upcoming")
        let response = try fixtureDecoder().decode(SessionsResponse.self, from: data)
        // May legitimately be empty for the seeded user — just prove it decodes.
        _ = response.sessions
    }

    func testRealFixture_sessionsRecent() throws {
        struct SessionsResponse: Decodable { let sessions: [SessionSummary] }
        let data = try loadFixture("sessions_recent")
        let response = try fixtureDecoder().decode(SessionsResponse.self, from: data)
        _ = response.sessions
    }

    func testRealFixture_dashboard() throws {
        let data = try loadFixture("dashboard")
        let stats = try fixtureDecoder().decode(DashboardStats.self, from: data)
        XCTAssertGreaterThanOrEqual(stats.sessionsFinalized, 0)
    }
}

// Not private: reused by SessionServiceTests.swift (same test target).
extension URLRequest {
    func httpBodyOrStream() throws -> Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
