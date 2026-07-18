/*
 * Purpose: Unit tests for SessionFlowService (F5 Task 1) — URLProtocol-stubbed
 *          request/response assertions for the B3 session-flow endpoints
 *          (negotiation, swap, recap gate, feedback report) plus decode checks
 *          against JSON byte-faithful to webapp/routes/session_flow.py and
 *          webapp/routes/practice_feedback.py.
 * Inputs: canned JSON strings.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

// Reuses StubURLProtocol defined in APIClientTests.swift (same test target).

final class SessionFlowNetworkingTests: XCTestCase {
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

    // MARK: - negotiation (interviewer view: pick_sources + a current pick)

    func testNegotiationInterviewerViewDecodesPickSources() async throws {
        stubJSON(#"""
        {"session_id": 42, "session_state": "negotiating", "your_role": "interviewer",
         "whose_turn": "candidate", "round_used": 1,
         "current_pick": {"case_id": 5, "title": "Widget Co", "case_type": "profitability", "difficulty": "medium"},
         "candidate_counter": null,
         "candidate_requested_case": null,
         "pick_sources": {
           "recommended_for_candidate": [
             {"case_id": 9, "title": "EV market sizing", "case_type": "market_sizing",
              "difficulty": "hard", "why": "Weak on structure", "rule": "focus_dimension"}
           ],
           "interviewer_done_set": [
             {"case_id": 7, "title": "Retail turnaround", "case_type": "profitability", "difficulty": "easy"}
           ],
           "library_allowed": true}}
        """#)

        let view = try await client.negotiation(id: 42)

        XCTAssertEqual(view.sessionId, 42)
        XCTAssertEqual(view.sessionState, "negotiating")
        XCTAssertEqual(view.yourRole, "interviewer")
        XCTAssertEqual(view.whoseTurn, "candidate")
        XCTAssertEqual(view.roundUsed, 1)
        XCTAssertEqual(view.currentPick?.caseId, 5)
        XCTAssertEqual(view.currentPick?.title, "Widget Co")
        XCTAssertEqual(view.currentPick?.caseType, "profitability")
        XCTAssertEqual(view.currentPick?.difficulty, "medium")
        XCTAssertNil(view.candidateCounter)
        XCTAssertNil(view.candidateRequestedCase)
        let sources = try XCTUnwrap(view.pickSources)
        XCTAssertEqual(sources.recommendedForCandidate.count, 1)
        XCTAssertEqual(sources.recommendedForCandidate[0].caseId, 9)
        XCTAssertEqual(sources.recommendedForCandidate[0].why, "Weak on structure")
        XCTAssertEqual(sources.recommendedForCandidate[0].rule, "focus_dimension")
        XCTAssertEqual(sources.interviewerDoneSet.count, 1)
        XCTAssertEqual(sources.interviewerDoneSet[0].caseId, 7)
        XCTAssertEqual(sources.interviewerDoneSet[0].difficulty, "easy")
        XCTAssertTrue(sources.libraryAllowed)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/negotiation")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - negotiation (candidate view: no pick_sources, null pick/counter)

    func testNegotiationCandidateViewNullPickAndNoSources() async throws {
        stubJSON(#"""
        {"session_id": 42, "session_state": "negotiating", "your_role": "candidate",
         "whose_turn": "interviewer", "round_used": 0,
         "current_pick": null, "candidate_counter": null,
         "candidate_requested_case": null}
        """#)

        let view = try await client.negotiation(id: 42)

        XCTAssertEqual(view.yourRole, "candidate")
        XCTAssertEqual(view.roundUsed, 0)
        XCTAssertNil(view.currentPick)
        XCTAssertNil(view.candidateCounter)
        XCTAssertNil(view.candidateRequestedCase)
        XCTAssertNil(view.pickSources)
    }

    // MARK: - negotiation with a candidate_requested_case present

    func testNegotiationDecodesRequestedCase() async throws {
        stubJSON(#"""
        {"session_id": 42, "session_state": "negotiating", "your_role": "interviewer",
         "whose_turn": "interviewer", "round_used": 0,
         "current_pick": null, "candidate_counter": null,
         "candidate_requested_case": {"case_id": 11, "title": "Airline pricing", "from_role": "candidate"},
         "pick_sources": {"recommended_for_candidate": [], "interviewer_done_set": [], "library_allowed": true}}
        """#)

        let view = try await client.negotiation(id: 42)

        let requested = try XCTUnwrap(view.candidateRequestedCase)
        XCTAssertEqual(requested.caseId, 11)
        XCTAssertEqual(requested.title, "Airline pricing")
        XCTAssertEqual(requested.fromRole, "candidate")
        XCTAssertEqual(view.pickSources?.recommendedForCandidate.count, 0)
    }

    // MARK: - proposeCase (POST body {case_id})

    func testProposeCaseRequestBodyAndDecode() async throws {
        stubJSON(#"""
        {"session_id": 42, "session_state": "negotiating", "your_role": "candidate",
         "whose_turn": "interviewer", "round_used": 2,
         "current_pick": {"case_id": 5, "title": "Widget Co", "case_type": null, "difficulty": null},
         "candidate_counter": {"case_id": 8, "title": "Bank ops", "case_type": "operations", "difficulty": "hard"},
         "candidate_requested_case": null}
        """#)

        let view = try await client.proposeCase(id: 42, caseId: 8)

        XCTAssertEqual(view.roundUsed, 2)
        XCTAssertEqual(view.candidateCounter?.caseId, 8)
        XCTAssertNil(view.currentPick?.caseType)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/negotiation/propose")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["case_id"] as? Int, 8)
    }

    // MARK: - acceptCase (returns SessionDetail, the stamped negotiating->lobby row)

    func testAcceptCaseReturnsSessionDetail() async throws {
        stubJSON(#"""
        {"id": 42, "interviewer_id": 1, "candidate_id": 2, "case_id": 8,
         "state": "lobby", "mode": "remote", "consent_interviewer": false, "consent_candidate": false,
         "scheduled_at": null, "started_at": null, "ended_at": null}
        """#)

        let detail = try await client.acceptCase(id: 42, caseId: 8)

        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.caseId, 8)
        XCTAssertEqual(detail.state, "lobby")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/negotiation/accept")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["case_id"] as? Int, 8)
    }

    // MARK: - swap (no body)

    func testSwapInitiateRequestAndDecode() async throws {
        stubJSON(#"{"swap_invite_id": 17, "invitee_id": 2}"#)

        let result = try await client.swap(id: 42)

        XCTAssertEqual(result.swapInviteId, 17)
        XCTAssertEqual(result.inviteeId, 2)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/swap")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    // MARK: - swapAccept

    func testSwapAcceptRequestAndDecode() async throws {
        stubJSON(#"{"accepted": true, "session_id": 99, "needs_negotiation": true}"#)

        let result = try await client.swapAccept(id: 42)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.sessionId, 99)
        XCTAssertTrue(result.needsNegotiation)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/swap/accept")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    // MARK: - recaps (unwrap {recaps: [...]})

    func testRecapsUnwrapAndDecode() async throws {
        stubJSON(#"""
        {"recaps": [
          {"session_id": 30, "case_id": 5, "case_title": "Widget Co",
           "grade": 4.2, "finalized_at": "2026-07-16T10:00:00+00:00",
           "viewed_at": null, "interviewer_name": "Alice Dev"},
          {"session_id": 31, "case_id": 6, "case_title": "Retail turnaround",
           "grade": null, "finalized_at": "2026-07-17T09:00:00+00:00",
           "viewed_at": "2026-07-17T09:05:00+00:00", "interviewer_name": null},
          {"session_id": 32, "case_id": 7, "case_title": null,
           "grade": null, "finalized_at": "2026-07-17T11:00:00+00:00",
           "viewed_at": null, "interviewer_name": "Carol Dev"}
        ]}
        """#)

        // Explicitly typed: APIClient also has F3's recaps() -> [RecapItem]
        // overload for the same endpoint (merge residual — unify later).
        let recaps: [RecapListItem] = try await client.recaps()

        XCTAssertEqual(recaps.count, 3)
        XCTAssertEqual(recaps[0].sessionId, 30)
        XCTAssertEqual(recaps[0].caseId, 5)
        XCTAssertEqual(recaps[0].caseTitle, "Widget Co")
        XCTAssertEqual(recaps[0].grade, 4.2)
        XCTAssertEqual(recaps[0].interviewerName, "Alice Dev")
        XCTAssertNil(recaps[0].viewedAt)
        XCTAssertNil(recaps[1].grade)
        XCTAssertNil(recaps[1].interviewerName)
        XCTAssertEqual(recaps[1].viewedAt, "2026-07-17T09:05:00+00:00")
        // Legacy row: LEFT-JOINed case_title is null and must decode to nil,
        // not fail the whole list decode.
        XCTAssertNil(recaps[2].caseTitle)
        XCTAssertEqual(recaps[2].caseId, 7)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/recaps")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - recapViewed

    func testRecapViewedRequestAndDecode() async throws {
        stubJSON(#"{"viewed": true}"#)

        let result = try await client.recapViewed(id: 30)

        XCTAssertTrue(result.viewed)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/30/recap/viewed")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    // MARK: - recapClose (POST body {case_rating, feedback_thumbs})

    func testRecapCloseRequestBodyAndDecode() async throws {
        stubJSON(#"{"closed": true, "gate_cleared": true}"#)

        let result = try await client.recapClose(id: 30, caseRating: 4, thumbs: true)

        XCTAssertTrue(result.closed)
        XCTAssertTrue(result.gateCleared)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/30/recap/close")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["case_rating"] as? Int, 4)
        XCTAssertEqual(body["feedback_thumbs"] as? Bool, true)
    }

    func testRecapCloseOmitsThumbsWhenNil() async throws {
        stubJSON(#"{"closed": true, "gate_cleared": false}"#)

        _ = try await client.recapClose(id: 30, caseRating: 3, thumbs: nil)

        let request = StubURLProtocol.recordedRequests.first!
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["case_rating"] as? Int, 3)
        XCTAssertFalse(body.keys.contains("feedback_thumbs"))
    }

    // MARK: - feedbackReport (items + notes_md + reveals)

    func testFeedbackReportDecode() async throws {
        stubJSON(#"""
        {"grade": 4.4, "finalized_at": "2026-07-16T15:00:00+00:00",
         "notes_md": "Strong structure, rushed the synthesis.",
         "items": [
           {"id": "structure", "label": "Structuring & framework", "dimension": "structure",
            "max_points": 5, "points": 4, "note": "Good MECE tree"},
           {"id": "math", "label": "Quant", "dimension": null, "max_points": 5, "points": 3, "note": ""}
         ],
         "reveals": [
           {"exhibit_id": 7, "idx": 0, "revealed_at": "2026-07-16T14:35:00+00:00", "t_offset_ms": 120000}
         ],
         "case_id": 5, "case_title": "Widget Co"}
        """#)

        let report = try await client.feedbackReport(id: 30)

        XCTAssertEqual(report.grade, 4.4)
        XCTAssertEqual(report.finalizedAt, "2026-07-16T15:00:00+00:00")
        XCTAssertEqual(report.notesMd, "Strong structure, rushed the synthesis.")
        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(report.items[0].id, "structure")
        XCTAssertEqual(report.items[0].maxPoints, 5)
        XCTAssertEqual(report.items[0].points, 4)
        XCTAssertEqual(report.items[0].note, "Good MECE tree")
        XCTAssertNil(report.items[1].dimension)
        XCTAssertEqual(report.reveals.count, 1)
        XCTAssertEqual(report.reveals[0].exhibitId, 7)
        XCTAssertEqual(report.reveals[0].idx, 0)
        XCTAssertEqual(report.reveals[0].tOffsetMs, 120000)
        XCTAssertEqual(report.caseId, 5)
        XCTAssertEqual(report.caseTitle, "Widget Co")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/30/feedback")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - finalize with next_recommendation + prefill_proposal (F5 additions)

    func testFinalizeDecodesNextRecommendationAndPrefill() async throws {
        stubJSON(#"""
        {"finalized": true, "grade": 4.4, "finalized_at": "2026-07-16T15:00:00+00:00",
         "next_recommendation": {"case_id": 9, "title": "EV market sizing", "case_type": "market_sizing",
           "difficulty": "hard", "why": "Weak on structure", "rule": "focus_dimension"},
         "prefill_proposal": {"to_user_id": 1, "case_id": 9}}
        """#)

        let result = try await client.finalize(id: 42, grade: 4.4)

        XCTAssertEqual(result.grade, 4.4)
        XCTAssertNotNil(result.finalizedAt)
        XCTAssertEqual(result.nextRecommendation?.caseId, 9)
        XCTAssertEqual(result.nextRecommendation?.title, "EV market sizing")
        XCTAssertEqual(result.prefillProposal?.toUserId, 1)
        XCTAssertEqual(result.prefillProposal?.caseId, 9)
    }

    // MARK: - finalize without the F5 debrief keys (back-compat)

    func testFinalizeDecodesWithoutNextRecommendation() async throws {
        stubJSON(#"{"finalized": true, "grade": 4.4, "finalized_at": "2026-07-16T15:00:00+00:00"}"#)

        let result = try await client.finalize(id: 42, grade: nil)

        XCTAssertEqual(result.grade, 4.4)
        XCTAssertNil(result.nextRecommendation)
        XCTAssertNil(result.prefillProposal)
    }

    func testFinalizeDecodesNullNextRecommendation() async throws {
        stubJSON(#"""
        {"finalized": true, "grade": 4.4, "finalized_at": "2026-07-16T15:00:00+00:00",
         "next_recommendation": null, "prefill_proposal": null}
        """#)

        let result = try await client.finalize(id: 42, grade: 4.4)

        XCTAssertNil(result.nextRecommendation)
        XCTAssertNil(result.prefillProposal)
    }

    // MARK: - recap-SEAT 409 decode helper

    func testRecapBlockSessionIDDecodesBlockedBody() {
        let data = Data(#"{"detail": {"blocked_by_recap": 30}}"#.utf8)
        XCTAssertEqual(APIClient.recapBlockSessionID(from: data), 30)
    }

    func testRecapBlockSessionIDReturnsNilForOtherDetail() {
        // A plain-string detail (e.g. a non-recap 409) must not match.
        XCTAssertNil(APIClient.recapBlockSessionID(from: Data(#"{"detail": "Swap already accepted"}"#.utf8)))
        XCTAssertNil(APIClient.recapBlockSessionID(from: Data(#"{"detail": {"other": 1}}"#.utf8)))
        XCTAssertNil(APIClient.recapBlockSessionID(from: Data("not json".utf8)))
    }
}
