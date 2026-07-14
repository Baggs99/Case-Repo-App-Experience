/*
 * Purpose: Splits a finished room-recording .m4a into sequential ≤8 MB byte
 *          chunks and uploads them via SessionService, resuming from the
 *          server's expected seq on a 409 (idempotent resend-nothing-twice).
 * Inputs: the recorded file's Data (or a file URL); sessionId; SessionService.
 * Outputs: none (network side effects: chunk uploads + completeRecording).
 * Run: try await RecordingUploader.upload(fileURL: recorder.stop(),
 *      sessionId: session.id, service: APIClient.shared) after debrief.
 */

import Foundation

enum RecordingUploader {
    static let maxChunkBytes = 8 * 1024 * 1024

    static func upload(fileURL: URL, sessionId: Int, service: SessionService) async throws {
        let data = try Data(contentsOf: fileURL)
        try await upload(data: data, sessionId: sessionId, service: service)
    }

    static func upload(
        data: Data, sessionId: Int, service: SessionService,
        chunkSize: Int = maxChunkBytes, mime: String = "audio/mp4"
    ) async throws {
        let chunks = chunked(data, size: chunkSize)

        var seq = 0
        // Tracks the `expected` seq from the prior mismatch so we can detect
        // a non-converging server: if it hands back the same `expected`
        // again with no progress in between, retrying forever would hang.
        var lastMismatchExpected: Int?
        while seq < chunks.count {
            do {
                try await service.uploadRecordingChunk(id: sessionId, seq: seq, mime: mime, blob: chunks[seq])
                seq += 1
                lastMismatchExpected = nil
            } catch RecordingChunkError.seqMismatch(let expected) {
                guard expected <= chunks.count else {
                    // A malformed resync target would fall past the array,
                    // exit the loop, and let completeRecording fire as if
                    // every chunk had been applied. Fail loudly instead.
                    throw RecordingChunkError.invalidExpectedSeq(expected: expected)
                }
                guard lastMismatchExpected != expected else {
                    // Same expected seq twice in a row — the server isn't
                    // converging. Never retry the identical chunk forever.
                    throw RecordingChunkError.stalled(seq: expected)
                }
                // Already-applied (expected < seq) or a gap (expected > seq) —
                // either way, resync to what the server says is next and
                // never re-send a chunk it already has.
                lastMismatchExpected = expected
                seq = expected
            }
        }

        try await service.completeRecording(id: sessionId)
    }

    private static func chunked(_ data: Data, size: Int) -> [Data] {
        guard !data.isEmpty else { return [] }
        var chunks: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = min(start + size, data.endIndex)
            chunks.append(data.subdata(in: start..<end))
            start = end
        }
        return chunks
    }
}
