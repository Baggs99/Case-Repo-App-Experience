/*
 * Purpose: Unit tests for F8 Task 1 — Community model decoding + the
 *          CommunityService API methods (B6 pinned shapes: connections,
 *          groups, group detail, group progress, school standing incl. the
 *          null-school dev-seed state and the drill_attempts_30d digit-
 *          boundary key).
 * Inputs: canned JSON strings, stubbed via StubURLProtocol (shared with
 *         APIClientTests.swift/LibraryDecodingTests.swift) so the real
 *         APIClient request+decode pipeline is exercised, not a private
 *         mirror.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class CommunityModelsTests: XCTestCase {
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

    // MARK: - connections()

    func testConnectionsRequestAndDecode() async throws {
        stubJSON(#"""
        {"connections": [
          {"user_id": 7, "display_name": "S. Park", "photo_url": null, "bio": "MBA '27",
           "free_now": true, "swap_invite_pending": false},
          {"user_id": 8, "display_name": "M. Lindqvist", "photo_url": "/avatars/8.png", "bio": null,
           "free_now": false, "swap_invite_pending": true}
        ]}
        """#)

        let connections = try await client.connections()

        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(connections[0].userId, 7)
        XCTAssertEqual(connections[0].id, 7)
        XCTAssertEqual(connections[0].displayName, "S. Park")
        XCTAssertNil(connections[0].photoUrl)
        XCTAssertTrue(connections[0].freeNow)
        XCTAssertFalse(connections[0].swapInvitePending)
        XCTAssertEqual(connections[1].photoUrl, "/avatars/8.png")
        XCTAssertNil(connections[1].bio)
        XCTAssertFalse(connections[1].freeNow)
        XCTAssertTrue(connections[1].swapInvitePending)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/connections")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - groups()

    func testGroupsRequestAndDecode() async throws {
        stubJSON(#"""
        {"groups": [{"id": 14, "name": "C-14", "school_id": 1, "invite_code": "C14-7QK2", "role": "member"}]}
        """#)

        let groups = try await client.groups()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, 14)
        XCTAssertEqual(groups[0].name, "C-14")
        XCTAssertEqual(groups[0].schoolId, 1)
        XCTAssertEqual(groups[0].inviteCode, "C14-7QK2")
        XCTAssertEqual(groups[0].role, "member")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - createGroup(name:)

    func testCreateGroupRequestBodyAndDecode() async throws {
        stubJSON(#"{"id": 20, "name": "New Cohort", "school_id": 1, "invite_code": "NC-8XQ1", "role": "admin"}"#)

        let group = try await client.createGroup(name: "New Cohort")

        XCTAssertEqual(group.id, 20)
        XCTAssertEqual(group.role, "admin")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["name"] as? String, "New Cohort")
    }

    // MARK: - group(id:) — GroupDetail (group + members + leaderboard)

    func testGroupDetailRequestAndDecode() async throws {
        stubJSON(#"""
        {"group": {"id": 14, "name": "C-14", "school_id": 1, "invite_code": "C14-7QK2"},
         "members": [{"user_id": 1, "display_name": "Amara Osei", "photo_url": null, "role": "admin"},
                     {"user_id": 2, "display_name": "R. Vance", "photo_url": null, "role": "member"}],
         "leaderboard": [{"user_id": 1, "display_name": "Amara Osei", "photo_url": null,
                          "points": 331, "rank": 6, "streak": 12}]}
        """#)

        let detail = try await client.group(id: 14)

        XCTAssertEqual(detail.group.id, 14)
        XCTAssertEqual(detail.group.name, "C-14")
        XCTAssertEqual(detail.group.schoolId, 1)
        XCTAssertEqual(detail.group.inviteCode, "C14-7QK2")
        XCTAssertEqual(detail.members.count, 2)
        XCTAssertEqual(detail.members[0].userId, 1)
        XCTAssertEqual(detail.members[0].role, "admin")
        XCTAssertEqual(detail.leaderboard.count, 1)
        XCTAssertEqual(detail.leaderboard[0].points, 331)
        XCTAssertEqual(detail.leaderboard[0].rank, 6)
        XCTAssertEqual(detail.leaderboard[0].streak, 12)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups/14")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - transferGroupAdmin(id:userId:)

    func testTransferGroupAdminSendsBody() async throws {
        stubJSON("", status: 200)

        try await client.transferGroupAdmin(id: 14, userId: 2)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups/14/transfer")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["user_id"] as? Int, 2)
    }

    // MARK: - groupProgress(id:) — the drill_attempts_30d digit-boundary key

    func testGroupProgressRequestAndDecode() async throws {
        stubJSON(#"""
        {"members": [
          {"user_id": 1, "display_name": "Amara Osei", "cases_done": 14, "mean_grade": 6.8,
           "drill_attempts_30d": 42, "streak": 12},
          {"user_id": 2, "display_name": "R. Vance", "cases_done": 0, "mean_grade": null,
           "drill_attempts_30d": 3, "streak": 1}
        ]}
        """#)

        let members = try await client.groupProgress(id: 14)

        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(members[0].userId, 1)
        XCTAssertEqual(members[0].id, 1)
        XCTAssertEqual(members[0].casesDone, 14)
        XCTAssertEqual(members[0].meanGrade, 6.8)
        XCTAssertEqual(members[0].drillAttempts30D, 42)
        XCTAssertEqual(members[0].streak, 12)
        XCTAssertNil(members[1].meanGrade)
        XCTAssertEqual(members[1].drillAttempts30D, 3)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups/14/progress")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - schoolStanding() — populated

    func testSchoolStandingRequestAndDecode() async throws {
        stubJSON(#"""
        {"school": {"school_id": 1, "name": "Wharton", "campus_city": "Philadelphia",
                    "avg_member_percentile": 69.8, "rank": 2},
         "your_percentile": 91.0}
        """#)

        let standing = try await client.schoolStanding()

        XCTAssertEqual(standing.school?.schoolId, 1)
        XCTAssertEqual(standing.school?.name, "Wharton")
        XCTAssertEqual(standing.school?.campusCity, "Philadelphia")
        XCTAssertEqual(standing.school?.avgMemberPercentile, 69.8)
        XCTAssertEqual(standing.school?.rank, 2)
        XCTAssertEqual(standing.yourPercentile, 91.0)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/leaderboards/school")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - schoolStanding() — null school (dev-seed state, Decisions §0.2:
    // never fabricate a count here)

    func testSchoolStandingNullSchoolDecodes() async throws {
        stubJSON(#"{"school": null, "your_percentile": null}"#)

        let standing = try await client.schoolStanding()

        XCTAssertNil(standing.school)
        XCTAssertNil(standing.yourPercentile)
    }
}
