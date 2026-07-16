/*
 * Purpose: Tests for ServerDrillEngine (unwraps the daily-drill envelope via a
 *          stubbed APIClient) and AttemptRecorder (posts once on success, queues
 *          on failure, and flushPending drains/preserves the queue).
 * Inputs: StubURLProtocol-backed APIClient; an in-memory MockDrillService; a
 *         scratch UserDefaults suite cleared per test.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

// In-memory DrillService for AttemptRecorder failure-injection tests.
final class MockDrillService: DrillService, @unchecked Sendable {
    var shouldFail = false
    var drillToReturn: Drill?
    private(set) var recordedAttempts: [(drillType: String, source: String, drillKey: String?, correct: Bool)] = []

    func dailyDrill() async throws -> Drill {
        if let drill = drillToReturn { return drill }
        throw APIError.server(500)
    }

    func templatePack() async throws -> Data { Data() }

    func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws {
        if shouldFail { throw APIError.server(500) }
        recordedAttempts.append((drillType, source, drillKey, correct))
    }
}

final class ServerDrillEngineTests: XCTestCase {
    private var client: APIClient!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = APIClient(session: URLSession(configuration: StubURLProtocol.sessionConfiguration))
        suiteName = "test.drills.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func stubJSON(_ json: String, status: Int = 200) {
        StubURLProtocol.stubs.append(
            .init(statusCode: status, data: Data(json.utf8), headers: ["Content-Type": "application/json"])
        )
    }

    private func makeDrill(key: String = "mm_markup_price") -> Drill {
        Drill(key: key, drillType: .mentalMath, prompt: "p", choices: nil,
              answer: DrillAnswer(kind: .numeric, value: 75, tolerancePct: 2,
                                  toleranceFactor: nil, correctIndex: nil),
              explanation: "e", numbers: ["50", "50"])
    }

    // MARK: - ServerDrillEngine

    func testServerEngineReturnsDecodedDrill() async throws {
        stubJSON(#"""
        {"drill": {"key": "mm_markup_price", "drill_type": "mental_math",
          "prompt": "A unit costs $50; add 50% markup. Selling price?",
          "answer": {"kind": "numeric", "value": 75.0, "tolerance_pct": 2.0},
          "explanation": "≈ $75.", "numbers": ["50", "50"]}, "date": "2026-07-16"}
        """#)

        let engine = ServerDrillEngine(service: client)
        let drill = try await engine.dailyDrill()

        XCTAssertEqual(drill.key, "mm_markup_price")
        XCTAssertEqual(drill.drillType, .mentalMath)
        XCTAssertEqual(drill.answer.value, 75.0)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/drills/daily")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testServerEngineSourceLabel() {
        let engine = ServerDrillEngine(service: client)
        XCTAssertEqual(engine.sourceLabel, "server")
    }

    // MARK: - AttemptRecorder success posts once

    func testRecordSuccessPostsOnceWithBody() async throws {
        stubJSON("", status: 204)
        let recorder = AttemptRecorder(service: client, defaults: defaults)

        await recorder.record(drill: makeDrill(), source: "server", correct: true)

        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 1)
        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/drills/attempts")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["drill_type"] as? String, "mental_math")
        XCTAssertEqual(body["source"] as? String, "server")
        XCTAssertEqual(body["drill_key"] as? String, "mm_markup_price")
        XCTAssertEqual(body["correct"] as? Bool, true)
        // Nothing queued on success.
        XCTAssertNil(defaults.array(forKey: "pendingDrillAttempts"))
    }

    // MARK: - AttemptRecorder failure enqueues

    func testRecordFailureEnqueues() async throws {
        let mock = MockDrillService()
        mock.shouldFail = true
        let recorder = AttemptRecorder(service: mock, defaults: defaults)

        await recorder.record(drill: makeDrill(), source: "on_device", correct: false)

        XCTAssertTrue(mock.recordedAttempts.isEmpty)
        let pending = try XCTUnwrap(pendingQueue())
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].drillType, "mental_math")
        XCTAssertEqual(pending[0].source, "on_device")
        XCTAssertEqual(pending[0].drillKey, "mm_markup_price")
        XCTAssertEqual(pending[0].correct, false)
    }

    // MARK: - flushPending drains on success

    func testFlushDrainsQueueOnSuccess() async throws {
        // Seed two pending attempts via a failing recorder.
        let failing = MockDrillService()
        failing.shouldFail = true
        let seeder = AttemptRecorder(service: failing, defaults: defaults)
        await seeder.record(drill: makeDrill(key: "a"), source: "server", correct: true)
        await seeder.record(drill: makeDrill(key: "b"), source: "server", correct: false)
        XCTAssertEqual(try XCTUnwrap(pendingQueue()).count, 2)

        let mock = MockDrillService()
        let recorder = AttemptRecorder(service: mock, defaults: defaults)
        await recorder.flushPending()

        XCTAssertEqual(mock.recordedAttempts.count, 2)
        XCTAssertTrue((pendingQueue() ?? []).isEmpty)
    }

    // MARK: - flushPending preserves on repeat failure

    func testFlushPreservesQueueOnRepeatFailure() async throws {
        let failing = MockDrillService()
        failing.shouldFail = true
        let seeder = AttemptRecorder(service: failing, defaults: defaults)
        await seeder.record(drill: makeDrill(key: "a"), source: "server", correct: true)
        await seeder.record(drill: makeDrill(key: "b"), source: "server", correct: false)

        let stillFailing = MockDrillService()
        stillFailing.shouldFail = true
        let recorder = AttemptRecorder(service: stillFailing, defaults: defaults)
        await recorder.flushPending()

        XCTAssertEqual(try XCTUnwrap(pendingQueue()).count, 2)
    }

    // Decodes the recorder's queue from the scratch suite.
    private func pendingQueue() -> [PendingAttempt]? {
        guard let data = defaults.data(forKey: "pendingDrillAttempts") else { return nil }
        return try? JSONDecoder().decode([PendingAttempt].self, from: data)
    }
}
