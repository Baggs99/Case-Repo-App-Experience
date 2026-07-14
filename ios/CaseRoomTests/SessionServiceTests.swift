/*
 * Purpose: Unit tests for SessionService (Task 7) — URLProtocol-stubbed
 *          request/response assertions for /api/practice endpoints plus
 *          decode checks for SessionDetail and RubricState against canned JSON.
 * Inputs: canned JSON strings.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

// Reuses StubURLProtocol defined in APIClientTests.swift (same test target).

final class SessionServiceTests: XCTestCase {
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

    // MARK: - sessionDetail

    func testSessionDetailRequestAndDecode() async throws {
        stubJSON(#"""
        {"id": 42, "interviewer_id": 1, "candidate_id": 2, "case_id": 5,
         "state": "lobby", "mode": "remote", "consent_interviewer": true, "consent_candidate": false,
         "scheduled_at": "2026-07-20T14:30:00+00:00", "started_at": null, "ended_at": null,
         "interviewer_name": "Alice Dev", "candidate_name": "Bob Dev",
         "case_title": "Widget Co", "your_role": "interviewer"}
        """#)

        let detail = try await client.sessionDetail(id: 42)

        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.interviewerId, 1)
        XCTAssertEqual(detail.candidateId, 2)
        XCTAssertEqual(detail.caseId, 5)
        XCTAssertEqual(detail.state, "lobby")
        XCTAssertEqual(detail.mode, "remote")
        XCTAssertTrue(detail.consentInterviewer)
        XCTAssertFalse(detail.consentCandidate)
        XCTAssertNotNil(detail.scheduledAt)
        XCTAssertNil(detail.startedAt)
        XCTAssertEqual(detail.interviewerName, "Alice Dev")
        XCTAssertEqual(detail.candidateName, "Bob Dev")
        XCTAssertEqual(detail.caseTitle, "Widget Co")
        XCTAssertEqual(detail.yourRole, "interviewer")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testSessionDetailDecodesWithoutNamesOrRole() throws {
        // /consent and /state return the bare session row (no joined
        // names/role) — the same SessionDetail model must still decode.
        let json = #"""
        {"id": 42, "interviewer_id": 1, "candidate_id": 2, "case_id": 5,
         "state": "lobby", "mode": "in_person", "consent_interviewer": true, "consent_candidate": false,
         "scheduled_at": null, "started_at": null, "ended_at": null}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(SessionDetail.self, from: Data(json.utf8))

        XCTAssertEqual(detail.mode, "in_person")
        XCTAssertNil(detail.interviewerName)
        XCTAssertNil(detail.yourRole)
    }

    // MARK: - setConsent

    func testSetConsentRequestAndDecode() async throws {
        stubJSON(#"""
        {"id": 42, "interviewer_id": 1, "candidate_id": 2, "case_id": 5,
         "state": "lobby", "mode": "remote", "consent_interviewer": true, "consent_candidate": true,
         "scheduled_at": null, "started_at": null, "ended_at": null}
        """#)

        let detail = try await client.setConsent(id: 42, consent: true)

        XCTAssertTrue(detail.consentCandidate)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/consent")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["consent"] as? Bool, true)
    }

    // MARK: - transition

    func testTransitionRequestAndDecode() async throws {
        stubJSON(#"""
        {"id": 42, "interviewer_id": 1, "candidate_id": 2, "case_id": 5,
         "state": "live", "mode": "remote", "consent_interviewer": true, "consent_candidate": true,
         "scheduled_at": null, "started_at": "2026-07-20T14:31:00+00:00", "ended_at": null}
        """#)

        let detail = try await client.transition(id: 42, target: "live")

        XCTAssertEqual(detail.state, "live")
        XCTAssertNotNil(detail.startedAt)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/state")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["target"] as? String, "live")
    }

    // MARK: - rubric

    func testRubricRequestAndDecode() async throws {
        stubJSON(#"""
        {"template_items": [{"id": "structure", "label": "Structuring & framework",
          "dimension": "structure", "max_points": 5}],
         "items": {"structure": {"points": 4, "note": "Good MECE tree"}},
         "notes_md": "Solid overall.", "grade_preview": 4.2, "grade": null, "finalized_at": null}
        """#)

        let rubric = try await client.rubric(id: 42)

        XCTAssertEqual(rubric.templateItems.count, 1)
        XCTAssertEqual(rubric.templateItems[0].id, "structure")
        XCTAssertEqual(rubric.templateItems[0].maxPoints, 5)
        XCTAssertEqual(rubric.items["structure"]?.points, 4)
        XCTAssertEqual(rubric.items["structure"]?.note, "Good MECE tree")
        XCTAssertEqual(rubric.notesMd, "Solid overall.")
        XCTAssertEqual(rubric.gradePreview, 4.2)
        XCTAssertNil(rubric.grade)
        XCTAssertNil(rubric.finalizedAt)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/rubric")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - saveRubric

    func testSaveRubricRequestBodyAndGradePreview() async throws {
        stubJSON(#"{"saved": true, "grade_preview": 4.4}"#)

        let gradePreview = try await client.saveRubric(
            id: 42,
            items: ["structure": RubricItemScore(points: 4, note: "Good MECE tree")],
            notesMd: "Solid overall."
        )

        XCTAssertEqual(gradePreview, 4.4)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/rubric")
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["notes_md"] as? String, "Solid overall.")
        let items = body["items"] as! [String: Any]
        let structure = items["structure"] as! [String: Any]
        XCTAssertEqual(structure["points"] as? Int, 4)
        XCTAssertEqual(structure["note"] as? String, "Good MECE tree")
    }

    // MARK: - reveal

    func testRevealRequestBody() async throws {
        stubJSON(#"{"session_id": 42, "exhibit_id": 7, "revealed_at": "2026-07-20T14:35:00+00:00"}"#)

        try await client.reveal(id: 42, exhibitId: 7)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/reveals")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["exhibit_id"] as? Int, 7)
    }

    // MARK: - exhibits

    func testExhibitsRequestAndDecode() async throws {
        stubJSON(#"""
        {"exhibits": [{"exhibit_id": 7, "idx": 0, "source_pages": "1-3",
          "width": 800, "height": 600, "bytes": 1024, "iv_b64": "abc123=="}]}
        """#)

        let exhibits = try await client.exhibits(id: 42)

        XCTAssertEqual(exhibits.count, 1)
        XCTAssertEqual(exhibits[0].exhibitId, 7)
        XCTAssertEqual(exhibits[0].sourcePages, "1-3")
        XCTAssertEqual(exhibits[0].ivB64, "abc123==")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/exhibits")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - exhibitBlob

    func testExhibitBlobRequestAndRawData() async throws {
        StubURLProtocol.stubs.append(
            .init(statusCode: 200, data: Data([0x01, 0x02, 0x03]),
                  headers: ["Content-Type": "application/octet-stream"])
        )

        let data = try await client.exhibitBlob(id: 42, exhibitId: 7)

        XCTAssertEqual(data, Data([0x01, 0x02, 0x03]))

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/exhibit-blob/7")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - uploadRecordingChunk

    func testUploadRecordingChunkMultipartBody() async throws {
        stubJSON(#"{"ok": true, "chunks": 1, "bytes": 3}"#)

        try await client.uploadRecordingChunk(id: 42, seq: 0, mime: "audio/webm", blob: Data([0xAA, 0xBB, 0xCC]))

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/recordings/chunk")
        XCTAssertEqual(request.httpMethod, "POST")
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let bodyData = try request.httpBodyOrStream()
        let bodyString = String(decoding: bodyData, as: UTF8.self)
        XCTAssertTrue(bodyString.contains("name=\"seq\""))
        XCTAssertTrue(bodyString.contains("\r\n0\r\n"))
        XCTAssertTrue(bodyString.contains("name=\"mime\""))
        XCTAssertTrue(bodyString.contains("audio/webm"))
        XCTAssertTrue(bodyString.contains("name=\"blob\""))
        XCTAssertNotNil(bodyData.range(of: Data([0xAA, 0xBB, 0xCC])))
        XCTAssertTrue(bodyString.hasSuffix("--\(boundary)--\r\n"))
    }

    func testUploadRecordingChunkSeqMismatchThrowsTypedError() async {
        stubJSON(#"{"detail": "expected seq 3"}"#, status: 409)

        do {
            try await client.uploadRecordingChunk(id: 42, seq: 0, mime: "audio/mp4", blob: Data([0xAA]))
            XCTFail("expected seqMismatch")
        } catch RecordingChunkError.seqMismatch(let expected) {
            XCTAssertEqual(expected, 3)
        } catch {
            XCTFail("expected RecordingChunkError.seqMismatch, got \(error)")
        }
    }

    // MARK: - completeRecording

    func testCompleteRecordingRequest() async throws {
        stubJSON(#"{"completed": true, "chunks": 3, "bytes": 900}"#)

        try await client.completeRecording(id: 42)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/recordings/complete")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    // MARK: - finalize

    func testFinalizeRequestBodyAndDecode() async throws {
        stubJSON(#"{"finalized": true, "grade": 4.4, "finalized_at": "2026-07-20T15:00:00+00:00"}"#)

        let result = try await client.finalize(id: 42, grade: 4.4)

        XCTAssertEqual(result.grade, 4.4)
        XCTAssertNotNil(result.finalizedAt)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/finalize")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["grade"] as? Double, 4.4)
    }

    func testFinalizeRequestBodyWithNilGrade() async throws {
        stubJSON(#"{"finalized": true, "grade": 4.4, "finalized_at": "2026-07-20T15:00:00+00:00"}"#)

        let result = try await client.finalize(id: 42, grade: nil)

        XCTAssertEqual(result.grade, 4.4)

        let request = StubURLProtocol.recordedRequests.first!
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertTrue(body.keys.contains("grade"))
        XCTAssertTrue(body["grade"] is NSNull)
    }

    // MARK: - joinConfig

    func testJoinConfigRequestAndDecode() async throws {
        stubJSON(#"""
        {"session_id": 42, "your_role": "interviewer", "ws_path": "/ws/practice/42",
         "ice_servers": [
           {"urls": ["stun:stun.example.com:19302"], "username": null, "credential": null},
           {"urls": ["turn:turn.example.com:3478"], "username": "turnuser", "credential": "turnpass"}
         ]}
        """#)

        let config = try await client.joinConfig(id: 42)

        XCTAssertEqual(config.sessionId, 42)
        XCTAssertEqual(config.yourRole, "interviewer")
        XCTAssertEqual(config.wsPath, "/ws/practice/42")
        XCTAssertEqual(config.iceServers.count, 2)
        XCTAssertEqual(config.iceServers[0].urls, ["stun:stun.example.com:19302"])
        XCTAssertNil(config.iceServers[0].username)
        XCTAssertNil(config.iceServers[0].credential)
        XCTAssertEqual(config.iceServers[1].urls, ["turn:turn.example.com:3478"])
        XCTAssertEqual(config.iceServers[1].username, "turnuser")
        XCTAssertEqual(config.iceServers[1].credential, "turnpass")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/practice/42/join-config")
        XCTAssertEqual(request.httpMethod, "GET")
    }
}
