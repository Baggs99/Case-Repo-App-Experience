/*
 * Purpose: Unit tests for WebRTCMediaCapture's toggle logic and the
 *          handle-type/shared-factory integration seam that
 *          RTCPeerConnectionWrapper.addLocalTracks depends on — driven with
 *          injected tracks (no camera, no live capture; that's Task 12
 *          real-device).
 * Inputs: none (in-memory RTCVideoTrack/RTCAudioTrack built from the shared
 *         factory, no capture session started).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CaseRoomTests/MediaCaptureTests
 */

import WebRTC
import XCTest
@testable import CaseRoom

final class MediaCaptureTests: XCTestCase {

    private func makeVideoTrack() -> RTCVideoTrack {
        let source = RTCMediaFactory.shared.videoSource()
        return RTCMediaFactory.shared.videoTrack(with: source, trackId: "test-video")
    }

    private func makeAudioTrack() -> RTCAudioTrack {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let source = RTCMediaFactory.shared.audioSource(with: constraints)
        return RTCMediaFactory.shared.audioTrack(with: source, trackId: "test-audio")
    }

    // MARK: - Toggle logic

    func testSetVideoEnabledFlipsInjectedTrack() {
        let videoTrack = makeVideoTrack()
        videoTrack.isEnabled = true
        let capture = WebRTCMediaCapture(videoTrack: videoTrack, audioTrack: nil)

        capture.setVideoEnabled(false)
        XCTAssertFalse(videoTrack.isEnabled)

        capture.setVideoEnabled(true)
        XCTAssertTrue(videoTrack.isEnabled)
    }

    func testSetAudioEnabledFlipsInjectedTrack() {
        let audioTrack = makeAudioTrack()
        audioTrack.isEnabled = true
        let capture = WebRTCMediaCapture(videoTrack: nil, audioTrack: audioTrack)

        capture.setAudioEnabled(false)
        XCTAssertFalse(audioTrack.isEnabled)

        capture.setAudioEnabled(true)
        XCTAssertTrue(audioTrack.isEnabled)
    }

    // MARK: - Handle-type compatibility (addLocalTracks drop-guard)

    // Regression guard: RTCPeerConnectionWrapper.addLocalTracks silently
    // skips any MediaTrackHandle that isn't its own concrete TrackHandle, so
    // WebRTCMediaCapture's local handles must be exactly that type or local
    // media is never sent (only catchable on a real device otherwise).
    func testLocalTrackHandlesAreAddLocalTracksCompatible() {
        let capture = WebRTCMediaCapture(videoTrack: makeVideoTrack(), audioTrack: makeAudioTrack())

        XCTAssertEqual(capture.localTrackHandles.count, 2)
        XCTAssertTrue(capture.localTrackHandles.allSatisfy { $0 is RTCPeerConnectionWrapper.TrackHandle })
    }

    func testNoTracksProducesNoLocalTrackHandles() {
        let capture = WebRTCMediaCapture(videoTrack: nil, audioTrack: nil)

        XCTAssertTrue(capture.localTrackHandles.isEmpty)
    }
}
