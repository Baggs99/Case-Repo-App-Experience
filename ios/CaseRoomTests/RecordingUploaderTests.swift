/*
 * Purpose: Unit tests for RecordingUploader's chunking + resumable-upload
 *          logic, isolated from a real file and a real network call via a
 *          stub SessionService.
 * Inputs: synthetic in-memory Data blobs.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

private final class StubRecordingService: SessionService {
    private(set) var recordedSeqs: [Int] = []
    private(set) var recordedBlobs: [Data] = []
    private(set) var completeRecordingCallCount = 0

    /// seq -> error to throw the first time that seq is attempted (then
    /// subsequent attempts at whatever seq the uploader retries succeed).
    var seqMismatchOnFirstAttempt: [Int: Int] = [:]
    private var attemptedOnce: Set<Int> = []

    /// When set, every attempt (any seq) is rejected with this `expected` —
    /// simulates a non-converging/buggy server for termination-guard tests.
    var alwaysMismatchExpected: Int?

    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws {
        if let expected = alwaysMismatchExpected {
            throw RecordingChunkError.seqMismatch(expected: expected)
        }
        if let expected = seqMismatchOnFirstAttempt[seq], !attemptedOnce.contains(seq) {
            attemptedOnce.insert(seq)
            throw RecordingChunkError.seqMismatch(expected: expected)
        }
        recordedSeqs.append(seq)
        recordedBlobs.append(blob)
    }

    func completeRecording(id: Int) async throws {
        completeRecordingCallCount += 1
    }

    // Unused by RecordingUploader — required by the SessionService protocol.
    func sessionDetail(id: Int) async throws -> SessionDetail { fatalError("not used") }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { fatalError("not used") }
    func transition(id: Int, target: String) async throws -> SessionDetail { fatalError("not used") }
    func rubric(id: Int) async throws -> RubricState { fatalError("not used") }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { fatalError("not used") }
    func reveal(id: Int, exhibitId: Int) async throws { fatalError("not used") }
    func exhibits(id: Int) async throws -> [ExhibitMeta] { fatalError("not used") }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { fatalError("not used") }
    func finalize(id: Int, grade: Double?) async throws { fatalError("not used") }
}

final class RecordingUploaderTests: XCTestCase {
    // 3 chunks of 4 bytes each from a 12-byte synthetic blob.
    private let syntheticBlob = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

    func testUploadsChunksInOrderThenCompletes() async throws {
        let service = StubRecordingService()

        try await RecordingUploader.upload(
            data: syntheticBlob, sessionId: 42, service: service, chunkSize: 4
        )

        XCTAssertEqual(service.recordedSeqs, [0, 1, 2])
        XCTAssertEqual(service.recordedBlobs, [
            Data([0, 1, 2, 3]), Data([4, 5, 6, 7]), Data([8, 9, 10, 11]),
        ])
        XCTAssertEqual(service.completeRecordingCallCount, 1)
    }

    func testResumesAtExpectedSeqOnMismatchWithoutLoopingForever() async throws {
        let service = StubRecordingService()
        // Server already has seq 0 applied — first attempt at seq 0 is
        // rejected with "expected seq 1"; the uploader must resync to 1
        // and continue, not re-send seq 0 endlessly.
        service.seqMismatchOnFirstAttempt = [0: 1]

        try await RecordingUploader.upload(
            data: syntheticBlob, sessionId: 42, service: service, chunkSize: 4
        )

        XCTAssertEqual(service.recordedSeqs, [1, 2])
        XCTAssertEqual(service.recordedBlobs, [
            Data([4, 5, 6, 7]), Data([8, 9, 10, 11]),
        ])
        XCTAssertEqual(service.completeRecordingCallCount, 1)
    }

    func testResyncsBackwardWhenServerAsksForEarlierSeqThenCompletes() async throws {
        let service = StubRecordingService()
        // Chunk 2 is sent, but the server claims it never saw chunk 1 —
        // expected (1) is LOWER than the seq (2) just sent. The uploader
        // must resend from 1 forward, not just resync forward-only.
        service.seqMismatchOnFirstAttempt = [2: 1]

        try await RecordingUploader.upload(
            data: syntheticBlob, sessionId: 42, service: service, chunkSize: 4
        )

        XCTAssertEqual(service.recordedSeqs, [0, 1, 1, 2])
        XCTAssertEqual(service.recordedBlobs, [
            Data([0, 1, 2, 3]), Data([4, 5, 6, 7]), Data([4, 5, 6, 7]), Data([8, 9, 10, 11]),
        ])
        XCTAssertEqual(service.completeRecordingCallCount, 1)
    }

    func testThrowsInsteadOfLoopingForeverWhenServerNeverConverges() async {
        let service = StubRecordingService()
        // A buggy/oscillating server that always hands back the same
        // "expected" seq must not be retried forever.
        service.alwaysMismatchExpected = 1

        do {
            try await RecordingUploader.upload(
                data: syntheticBlob, sessionId: 42, service: service, chunkSize: 4
            )
            XCTFail("expected RecordingChunkError.stalled to be thrown")
        } catch RecordingChunkError.stalled(let seq) {
            XCTAssertEqual(seq, 1)
        } catch {
            XCTFail("expected .stalled, got \(error)")
        }

        XCTAssertEqual(service.completeRecordingCallCount, 0)
    }
}
