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

    // MARK: - availability

    func testAvailabilityRequestAndDecode() async throws {
        stubJSON(#"""
        {"free_until": "2026-07-16T18:00:00+00:00", "others": [
          {"user_id": 7, "name": "Bob Dev", "free_until": "2026-07-16T18:30:00+00:00"}]}
        """#)

        let status = try await client.availability()

        XCTAssertNotNil(status.freeUntil)
        XCTAssertEqual(status.others.count, 1)
        XCTAssertEqual(status.others[0].userId, 7)
        XCTAssertEqual(status.others[0].name, "Bob Dev")
        XCTAssertEqual(status.others[0].id, 7)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/availability")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testAvailabilityNullFreeUntilDecodes() async throws {
        stubJSON(#"{"free_until": null, "others": []}"#)

        let status = try await client.availability()

        XCTAssertNil(status.freeUntil)
        XCTAssertTrue(status.others.isEmpty)
    }

    func testSetFreeRequestBodyAndDecode() async throws {
        stubJSON(#"{"free_until": "2026-07-16T18:00:00+00:00", "others": []}"#)

        let status = try await client.setFree(minutes: 45)

        XCTAssertNotNil(status.freeUntil)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/availability")
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["minutes"] as? Int, 45)
    }

    func testClearFreeSendsDelete() async throws {
        stubJSON("", status: 204)

        try await client.clearFree()

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/availability")
        XCTAssertEqual(request.httpMethod, "DELETE")
    }

    // MARK: - createProposal

    func testCreateProposalPostsBodyAndSucceedsAgainstBareRow() async throws {
        // The server returns the bare proposals-table row (proposed_times_json,
        // no from_name/case_title) — NOT the enriched Proposal shape. The client
        // discards it, so this must succeed even though the body can't decode
        // into Proposal. Mirrors webapp/repositories/proposals._COLS RETURNING.
        stubJSON(#"""
        {"id": 42, "from_user_id": 1, "to_user_id": 7, "case_id": 5,
          "from_role": "interviewer", "message": "now?",
          "proposed_times_json": ["2026-07-16T18:00:00+00:00"],
          "state": "pending", "session_id": null,
          "created_at": "2026-07-16T17:00:00+00:00", "responded_at": null}
        """#)

        try await client.createProposal(
            toUserId: 7, caseId: 5, fromRole: "interviewer", message: "now?"
        )

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/proposals")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["to_user_id"] as? Int, 7)
        XCTAssertEqual(body["case_id"] as? Int, 5)
        XCTAssertEqual(body["from_role"] as? String, "interviewer")
        XCTAssertEqual(body["message"] as? String, "now?")
        let times = body["proposed_times"] as? [Any]
        XCTAssertEqual(times?.count, 1)
        XCTAssertTrue(times?.first is String)
    }

    func testCreateProposalOmitsNilMessage() async throws {
        stubJSON(#"""
        {"id": 43, "from_user_id": 1, "to_user_id": 8, "case_id": 6,
          "from_role": "candidate", "message": null,
          "proposed_times_json": ["2026-07-16T18:00:00+00:00"],
          "state": "pending", "session_id": null,
          "created_at": "2026-07-16T17:00:00+00:00", "responded_at": null}
        """#)

        try await client.createProposal(
            toUserId: 8, caseId: 6, fromRole: "candidate", message: nil
        )

        let request = StubURLProtocol.recordedRequests.first!
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertNil(body["message"])
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

    // MARK: - App Group session configuration

    // The default APIClient session must have a cookie store — the group store
    // when the container resolves, or HTTPCookieStorage.shared as the
    // unprovisioned/dev-build fallback. Either way it is never nil, so cookie
    // auth keeps working.
    func testGroupSessionConfigurationHasCookieStorage() {
        let config = AppGroup.makeURLSessionConfiguration()

        XCTAssertNotNil(config.httpCookieStorage)
    }

    // Cookie migration copies the API host's cookies into the destination and
    // is idempotent: HTTPCookieStorage keys cookies by (domain, path, name), so
    // running the copy twice replaces rather than duplicates. A scratch source/
    // destination pair keeps the assertion off any global cookie store.
    func testCookieMigrationCopyIsIdempotent() throws {
        let source = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let destination = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "session",
            .value: "abc123",
        ]))
        source.setCookie(cookie)

        AppGroup.copyCookies(for: "127.0.0.1", from: source, into: destination)
        AppGroup.copyCookies(for: "127.0.0.1", from: source, into: destination)

        let sessionCookies = (destination.cookies ?? []).filter { $0.name == "session" }
        XCTAssertEqual(sessionCookies.count, 1)
        XCTAssertEqual(sessionCookies.first?.value, "abc123")
    }

    // A cookie for an unrelated host is not swept into the destination.
    func testCookieMigrationCopyIgnoresOtherHosts() throws {
        let source = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let destination = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let other = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "nope",
        ]))
        source.setCookie(other)

        AppGroup.copyCookies(for: "127.0.0.1", from: source, into: destination)

        XCTAssertTrue((destination.cookies ?? []).isEmpty)
    }

    // MARK: - Profile

    func testProfileDecodesNullableFields() async throws {
        stubJSON(#"{"id":5,"email":"a@yale.edu","display_name":"Amara Osei","bio":null,"linkedin_url":"https://linkedin.com/in/amara","school":"Wharton","photo_url":"/avatars/5.jpg"}"#)
        let p = try await client.profile()
        XCTAssertEqual(p.id, 5)
        XCTAssertEqual(p.displayName, "Amara Osei")
        XCTAssertNil(p.bio)
        XCTAssertEqual(p.linkedinUrl, "https://linkedin.com/in/amara")
        XCTAssertEqual(p.school, "Wharton")
        XCTAssertEqual(p.photoUrl, "/avatars/5.jpg")
        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.url?.path, "/api/v1/profile")
        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.httpMethod, "GET")
    }

    func testUpdateProfileEncodesSnakeCase() async throws {
        stubJSON(#"{"id":5,"email":"a@yale.edu","display_name":"New Name","bio":"hi","linkedin_url":null,"school":"Wharton","photo_url":null}"#)
        _ = try await client.updateProfile(displayName: "New Name", bio: "hi", linkedinUrl: nil)
        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/profile")
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["display_name"] as? String, "New Name")
        XCTAssertEqual(body["bio"] as? String, "hi")
    }

    func testUploadPhotoReturnsURLAndSendsMultipart() async throws {
        stubJSON(#"{"photo_url":"/avatars/5.png"}"#)
        let url = try await client.uploadProfilePhoto(data: Data([0x89, 0x50]), mime: "image/png")
        XCTAssertEqual(url, "/avatars/5.png")
        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/profile/photo")
        XCTAssertEqual(request.httpMethod, "POST")
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
    }

    // MARK: - Notification settings

    func testNotificationSettingsDecodesFiveBools() async throws {
        stubJSON(#"{"proposals":true,"session_reminders":false,"feedback":true,"free_now":false,"community":true}"#)
        let s = try await client.notificationSettings()
        XCTAssertTrue(s.proposals)
        XCTAssertFalse(s.sessionReminders)
        XCTAssertTrue(s.feedback)
        XCTAssertFalse(s.freeNow)
        XCTAssertTrue(s.community)
        XCTAssertFalse(s.allEnabled)
        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.url?.path, "/api/v1/settings/notifications")
    }

    func testUpdateNotificationSettingsRoundTrips() async throws {
        stubJSON(#"{"proposals":false,"session_reminders":false,"feedback":false,"free_now":false,"community":false}"#)
        let all = NotificationSettings(proposals: false, sessionReminders: false, feedback: false, freeNow: false, community: false)
        let s = try await client.updateNotificationSettings(all)
        XCTAssertFalse(s.allEnabled)
        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/settings/notifications")
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["free_now"] as? Bool, false)
    }

    // MARK: - Dashboard extensions (B4/B7, Task 2)

    // Pastes the extended /api/v1/dashboard shape (webapp/routes/api_v1.py:372-396)
    // verbatim and asserts every new field, including the diagnostic
    // strengths/weaknesses dimension-score rows (dashboard.py:317-339 — not
    // plain strings, confirmed against source).
    func testDashboardDecodesExtendedFields() async throws {
        stubJSON(#"""
        {"sessions_finalized": 4, "streak_weeks": 2, "next_session": null,
         "streak_days": 6, "drill_done_today": true,
         "dimension_averages": [{"dimension": "quant", "avg_score": 3.2, "samples": 8}],
         "recommendations": [{"case_id": 11, "title": "Widget Co", "case_type": "Profitability",
           "difficulty": "Medium", "why": "Your weakest dimension is quant.", "rule": "weak-dimension"}],
         "diagnostic": {"cases_done_60d": 5,
           "dimensions": [{"dimension": "quant", "avg_score": 3.2, "samples": 8},
                           {"dimension": "structure", "avg_score": 4.1, "samples": 8}],
           "strengths": [{"dimension": "structure", "avg_score": 4.1, "samples": 8}],
           "weaknesses": [{"dimension": "quant", "avg_score": 3.2, "samples": 8}],
           "focus_dimension": "quant",
           "trend": {"recent_avg": 4.0, "previous_avg": 3.5, "delta": 0.5, "direction": "up"}},
         "timeline": {"tracked_count": 2, "next_deadline": {"firm_id": 3, "name": "McKinsey",
           "slug": "mckinsey", "cycle_label": "Fall", "deadline_date": "2026-09-12",
           "days_remaining": 58, "readiness_tag": "on_track"}}}
        """#)

        let stats = try await client.dashboard()

        XCTAssertEqual(stats.sessionsFinalized, 4)
        XCTAssertEqual(stats.streakDays, 6)
        XCTAssertEqual(stats.dimensionAverages?.first?.dimension, "quant")
        XCTAssertEqual(stats.dimensionAverages?.first?.avgScore, 3.2)
        XCTAssertEqual(stats.recommendations?.first?.title, "Widget Co")
        XCTAssertEqual(stats.recommendations?.first?.caseId, 11)
        XCTAssertEqual(stats.diagnostic?.casesDone60D, 5)
        XCTAssertEqual(stats.diagnostic?.dimensions.count, 2)
        XCTAssertEqual(stats.diagnostic?.strengths.first?.dimension, "structure")
        XCTAssertEqual(stats.diagnostic?.weaknesses.first?.dimension, "quant")
        XCTAssertEqual(stats.diagnostic?.focusDimension, "quant")
        XCTAssertEqual(stats.diagnostic?.trend.direction, "up")
        XCTAssertEqual(stats.timeline?.trackedCount, 2)
        XCTAssertEqual(stats.timeline?.nextDeadline?.name, "McKinsey")
        XCTAssertEqual(stats.timeline?.nextDeadline?.daysRemaining, 58)
    }

    // Legacy payload (no B4/B7 keys at all) must still decode — proves the
    // extension is additive/back-compat, not just optional-when-present.
    func testDashboardLegacyPayloadWithoutHomeFieldsStillDecodes() async throws {
        stubJSON(#"""
        {"sessions_finalized": 1, "streak_weeks": 1, "next_session": null}
        """#)

        let stats = try await client.dashboard()

        XCTAssertEqual(stats.sessionsFinalized, 1)
        XCTAssertNil(stats.streakDays)
        XCTAssertNil(stats.dimensionAverages)
        XCTAssertNil(stats.recommendations)
        XCTAssertNil(stats.diagnostic)
        XCTAssertNil(stats.timeline)
    }

    // MARK: - Timeline detail (B7, Task 2)

    func testTimelineRequestAndDecode() async throws {
        stubJSON(#"""
        {"as_of": "2026-07-17", "readiness": {"label": "on_track", "ready": true,
          "focus_dimension": "quant", "recent_case_count": 6, "threshold": 3.5, "min_cases": 5},
         "firms": [{"firm_id": 3, "name": "McKinsey", "slug": "mckinsey", "status": "tracking",
           "added_at": "2026-06-01T10:00:00+00:00",
           "deadline": {"cycle_label": "Fall", "deadline_date": "2026-09-12", "region": "Americas",
             "is_estimate": false, "days_remaining": 58, "passed": false},
           "readiness_tag": "on_track", "prompt": {"show": false}}]}
        """#)

        let detail = try await client.timeline()

        XCTAssertEqual(detail.asOf, "2026-07-17")
        XCTAssertEqual(detail.readiness.label, "on_track")
        XCTAssertTrue(detail.readiness.ready)
        XCTAssertEqual(detail.readiness.focusDimension, "quant")
        XCTAssertEqual(detail.firms.count, 1)
        XCTAssertEqual(detail.firms[0].name, "McKinsey")
        XCTAssertEqual(detail.firms[0].deadline?.daysRemaining, 58)
        XCTAssertFalse(detail.firms[0].deadline?.passed ?? true)
        XCTAssertFalse(detail.firms[0].prompt.show)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/timeline")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testTimelineFirmsCatalogRequestAndDecode() async throws {
        stubJSON(#"""
        {"firms": [{"firm_id": 3, "name": "McKinsey", "slug": "mckinsey", "tracked": true,
           "next_deadline": {"cycle_label": "Fall", "deadline_date": "2026-09-12", "region": "Americas",
             "is_estimate": false, "days_remaining": 58, "passed": false}},
          {"firm_id": 4, "name": "BCG", "slug": "bcg", "tracked": false, "next_deadline": null}]}
        """#)

        let firms = try await client.timelineFirms()

        XCTAssertEqual(firms.count, 2)
        XCTAssertEqual(firms[0].name, "McKinsey")
        XCTAssertTrue(firms[0].tracked)
        XCTAssertEqual(firms[1].name, "BCG")
        XCTAssertFalse(firms[1].tracked)
        XCTAssertNil(firms[1].nextDeadline)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/timeline/firms")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testTrackFirmPostsBody() async throws {
        stubJSON("", status: 204)

        try await client.trackFirm(firmId: 4)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/timeline/firms")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["firm_id"] as? Int, 4)
    }

    func testUntrackFirmSendsDelete() async throws {
        stubJSON("", status: 204)

        try await client.untrackFirm(firmId: 4)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/timeline/firms/4")
        XCTAssertEqual(request.httpMethod, "DELETE")
    }

    // Four firm-result outcomes (webapp/routes/timeline.py:71-96) — every
    // outcome shares one FirmResult shape but populates different fields.

    func testFirmResultOfferOutcomeDecodes() async throws {
        stubJSON(#"{"outcome": "offer", "status": "offer", "result_recorded_at": "2026-07-17T09:00:00+00:00"}"#)

        let result = try await client.firmResult(firmId: 3, outcome: "offer")

        XCTAssertEqual(result.outcome, "offer")
        XCTAssertEqual(result.status, "offer")
        XCTAssertEqual(result.resultRecordedAt, "2026-07-17T09:00:00+00:00")
        XCTAssertNil(result.reweight)
        XCTAssertNil(result.snoozeUntil)
        XCTAssertNil(result.dropped)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/timeline/firms/3/result")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["outcome"] as? String, "offer")
    }

    func testFirmResultNoOfferOutcomeDecodesReweight() async throws {
        stubJSON(#"""
        {"outcome": "no_offer", "status": "rejected",
         "reweight": {"focus_dimension": "quant", "suggested_drill_type": "mental_math",
           "extra_cases": [12, 19]}}
        """#)

        let result = try await client.firmResult(firmId: 3, outcome: "no_offer")

        XCTAssertEqual(result.outcome, "no_offer")
        XCTAssertEqual(result.status, "rejected")
        XCTAssertEqual(result.reweight?.focusDimension, "quant")
        XCTAssertEqual(result.reweight?.suggestedDrillType, "mental_math")
        XCTAssertEqual(result.reweight?.extraCases, [12, 19])
    }

    // readiness.py emits focus_dimension: null for a user with no finalized
    // candidate sessions — the whole FirmResult must still decode.
    func testFirmResultNoOfferReweightAllowsNullFocusDimension() async throws {
        stubJSON(#"""
        {"outcome": "no_offer", "status": "rejected",
         "reweight": {"focus_dimension": null, "suggested_drill_type": "market_sizing",
           "extra_cases": []}}
        """#)

        let result = try await client.firmResult(firmId: 3, outcome: "no_offer")

        XCTAssertEqual(result.outcome, "no_offer")
        XCTAssertNil(result.reweight?.focusDimension)
        XCTAssertEqual(result.reweight?.suggestedDrillType, "market_sizing")
        XCTAssertEqual(result.reweight?.extraCases, [])
    }

    func testFirmResultWaitingOutcomeDecodesSnoozeUntil() async throws {
        stubJSON(#"{"outcome": "waiting", "status": "interviewed", "snooze_until": "2026-07-24"}"#)

        let result = try await client.firmResult(firmId: 3, outcome: "waiting")

        XCTAssertEqual(result.outcome, "waiting")
        XCTAssertEqual(result.status, "interviewed")
        XCTAssertEqual(result.snoozeUntil, "2026-07-24")
    }

    func testFirmResultDidntInterviewOutcomeDecodesDropped() async throws {
        stubJSON(#"{"outcome": "didnt_interview", "dropped": true}"#)

        let result = try await client.firmResult(firmId: 3, outcome: "didnt_interview")

        XCTAssertEqual(result.outcome, "didnt_interview")
        XCTAssertEqual(result.dropped, true)
        XCTAssertNil(result.status)
    }

    // MARK: - Recommendations (B4, Task 2)

    func testRecommendationsRequestOmitsExcludeWhenEmpty() async throws {
        stubJSON(#"{"recommendations": []}"#)

        let recs = try await client.recommendations(exclude: [])

        XCTAssertTrue(recs.isEmpty)
        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/recommendations")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertTrue(query.isEmpty)
    }

    func testRecommendationsRequestJoinsExcludeIdsWithCommas() async throws {
        stubJSON(#"""
        {"recommendations": [{"case_id": 22, "title": "Beta Corp", "case_type": "Market Sizing",
          "difficulty": "Hard", "why": "Coverage gap.", "rule": "coverage-gap"}]}
        """#)

        let recs = try await client.recommendations(exclude: [11, 12, 13])

        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].caseId, 22)
        XCTAssertEqual(recs[0].title, "Beta Corp")
        let request = StubURLProtocol.recordedRequests.first!
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "exclude", value: "11,12,13")))
    }

    // MARK: - Gauntlet (B8, Task 2)

    func testGauntletUnsubmittedDecodesNilResult() async throws {
        stubJSON(#"""
        {"date": "2026-07-17", "set_key": "2026-07-17", "provisional": true,
         "slots": [{"slot": 0, "drill_type": "mental_math", "key": "mm-1",
           "prompt": "12% of 480?", "numbers": ["12", "480"]},
          {"slot": 1, "drill_type": "framework_recall", "key": "fr-1",
           "prompt": "Which framework?", "numbers": [], "choices": ["4Ps", "Porter's Five"]}],
         "streak": 3, "submitted": false, "result": null}
        """#)

        let gauntlet = try await client.gauntlet()

        XCTAssertEqual(gauntlet.setKey, "2026-07-17")
        XCTAssertEqual(gauntlet.slots.count, 2)
        XCTAssertEqual(gauntlet.slots[0].drillType, "mental_math")
        XCTAssertNil(gauntlet.slots[0].choices)
        XCTAssertEqual(gauntlet.slots[1].choices, ["4Ps", "Porter's Five"])
        XCTAssertFalse(gauntlet.submitted)
        XCTAssertNil(gauntlet.result)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/drills/gauntlet")
    }

    func testGauntletSubmittedDecodesResult() async throws {
        stubJSON(#"""
        {"date": "2026-07-17", "set_key": "2026-07-17", "provisional": true,
         "slots": [{"slot": 0, "drill_type": "mental_math", "key": "mm-1",
           "prompt": "12% of 480?", "numbers": ["12", "480"]}],
         "streak": 4, "submitted": true,
         "result": {"score": 0.83, "slots_correct": 5, "slots": 6, "points_awarded": 50,
           "daily_percentile": 72.5,
           "group": {"group_id": 9, "name": "Yale SOM 26", "rank": 2, "points": 340, "points_behind_next": 15},
           "school_percentile": 60.0, "vs_peers_delta": 15,
           "weak_section": {"drill_type": "market_sizing", "label": "market sizing"},
           "streak": 4, "set_key": "2026-07-17"}}
        """#)

        let gauntlet = try await client.gauntlet()

        XCTAssertTrue(gauntlet.submitted)
        XCTAssertEqual(gauntlet.result?.score, 0.83)
        XCTAssertEqual(gauntlet.result?.slotsCorrect, 5)
        XCTAssertEqual(gauntlet.result?.group?.name, "Yale SOM 26")
        XCTAssertEqual(gauntlet.result?.group?.rank, 2)
        XCTAssertEqual(gauntlet.result?.group?.pointsBehindNext, 15)
        XCTAssertEqual(gauntlet.result?.weakSection?.drillType, "market_sizing")
        XCTAssertEqual(gauntlet.result?.vsPeersDelta, 15)
    }

    // MARK: - Group board (B8, Task 2)

    func testGroupBoardRequestAndDecode() async throws {
        stubJSON(#"""
        {"scope": "group", "group": {"id": 9, "name": "Yale SOM 26"},
         "entries": [{"user_id": 1, "display_name": "Alice Dev", "photo_key": "avatars/1.jpg",
            "points": 340, "rank": 1, "streak": 6},
           {"user_id": 2, "display_name": "Bob Dev", "photo_key": null,
            "points": 300, "rank": 2, "streak": 3}]}
        """#)

        let board = try await client.groupBoard()

        XCTAssertEqual(board.scope, "group")
        XCTAssertEqual(board.group?.name, "Yale SOM 26")
        XCTAssertEqual(board.entries.count, 2)
        XCTAssertEqual(board.entries[0].displayName, "Alice Dev")
        XCTAssertEqual(board.entries[1].photoKey, nil)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/drills/boards")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "scope", value: "group")))
    }

    func testGroupBoardEmptyGroupDecodesNilGroupAndEntries() async throws {
        stubJSON(#"{"scope": "group", "group": null, "entries": []}"#)

        let board = try await client.groupBoard()

        XCTAssertNil(board.group)
        XCTAssertTrue(board.entries.isEmpty)
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
