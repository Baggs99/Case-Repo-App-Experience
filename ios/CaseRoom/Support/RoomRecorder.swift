/*
 * Purpose: Captures room audio as AAC .m4a during a live practice session,
 *          using AVAudioSession record permission + AVAudioRecorder.
 * Inputs: NSMicrophoneUsageDescription-gated mic permission.
 * Outputs: a temp-directory .m4a file, returned by stop().
 * Run: let recorder = RoomRecorder(); try await recorder.start() on go-live;
 *      let fileURL = recorder.stop() on debrief, then hand fileURL to
 *      RecordingUploader.upload(fileURL:sessionId:service:).
 */

import AVFoundation
import Foundation

enum RoomRecorderError: Error {
    case permissionDenied
}

final class RoomRecorder {
    let fileURL: URL
    private var recorder: AVAudioRecorder?

    init() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }

    func start() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw RoomRecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.record()
        self.recorder = recorder
    }

    @discardableResult
    func stop() -> URL {
        recorder?.stop()
        recorder = nil
        return fileURL
    }
}
