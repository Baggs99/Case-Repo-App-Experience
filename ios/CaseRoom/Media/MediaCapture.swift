/*
 * Purpose: Local camera/mic capture behind MediaCapturing so the simulator
 *          build + unit tests need no camera; WebRTCMediaCapture is the
 *          only type here that drives RTCCameraVideoCapturer, and it shares
 *          RTCPeerConnectionWrapper's RTCPeerConnectionFactory (WebRTC
 *          requires tracks and the peer connection that sends them to come
 *          from the same factory) and hands out RTCPeerConnectionWrapper's
 *          own TrackHandle type so addLocalTracks doesn't silently drop it.
 * Inputs: none at init; start(video:audio:) requests camera/mic capture.
 * Outputs: local RTCVideoTrack/RTCAudioTrack side effects; localTrackHandles
 *          for MediaTransport.addLocalTracks.
 * Run: consumed by VideoCallView and Task 8's session screen; see
 *      ios/CaseRoomTests/MediaCaptureTests.swift for toggle-logic coverage.
 */

import AVFoundation
import WebRTC

// MARK: - Shared factory

/// WebRTC requires media tracks and the RTCPeerConnection that sends them to
/// come from the same RTCPeerConnectionFactory, so this instance is shared
/// between WebRTCMediaCapture and RTCPeerConnectionWrapper instead of each
/// owning its own.
enum RTCMediaFactory {
    static let shared = RTCPeerConnectionFactory()
}

// MARK: - MediaCapturing

/// Local capture surface for the video-call view. Kept behind a protocol so
/// the simulator build + unit tests can use a no-camera stub in place of
/// WebRTCMediaCapture. The remote track is NOT part of this protocol — it
/// originates from MediaTransport.onRemoteTrack (Task 8), not capture.
protocol MediaCapturing: AnyObject {
    func start(video: Bool, audio: Bool) throws
    func setVideoEnabled(_ enabled: Bool)
    func setAudioEnabled(_ enabled: Bool)
    /// Local track handles for MediaTransport.addLocalTracks. Concrete
    /// instances MUST be RTCPeerConnectionWrapper.TrackHandle — any other
    /// MediaTrackHandle is silently skipped by addLocalTracks.
    var localTrackHandles: [MediaTrackHandle] { get }
    func stop()
}

// MARK: - WebRTCMediaCapture

final class WebRTCMediaCapture: MediaCapturing {
    private var videoTrack: RTCVideoTrack?
    private var audioTrack: RTCAudioTrack?
    private var capturer: RTCCameraVideoCapturer?

    init() {}

    /// Test seam: inject already-built tracks (no capture session, no
    /// camera/mic hardware) so the toggle logic is testable in the
    /// simulator. RTCVideoTrack/RTCAudioTrack can be constructed from the
    /// shared factory without ever starting a capture session.
    init(videoTrack: RTCVideoTrack?, audioTrack: RTCAudioTrack?) {
        self.videoTrack = videoTrack
        self.audioTrack = audioTrack
    }

    var localTrackHandles: [MediaTrackHandle] {
        [videoTrack, audioTrack]
            .compactMap { $0 }
            .map { RTCPeerConnectionWrapper.TrackHandle(track: $0) }
    }

    func start(video: Bool, audio: Bool) throws {
        if video {
            let source = RTCMediaFactory.shared.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: source)
            self.capturer = capturer
            startCameraCapture(with: capturer)
            videoTrack = RTCMediaFactory.shared.videoTrack(with: source, trackId: "video0")
        }
        if audio {
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let source = RTCMediaFactory.shared.audioSource(with: constraints)
            audioTrack = RTCMediaFactory.shared.audioTrack(with: source, trackId: "audio0")
        }
    }

    func setVideoEnabled(_ enabled: Bool) {
        videoTrack?.isEnabled = enabled
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioTrack?.isEnabled = enabled
    }

    func stop() {
        capturer?.stopCapture()
        capturer = nil
        videoTrack = nil
        audioTrack = nil
    }

    // Best-effort front-camera start. The simulator has no capture devices
    // so this is a no-op there by design — real capture is exercised on a
    // device only (Task 12).
    private func startCameraCapture(with capturer: RTCCameraVideoCapturer) {
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard
            let device = devices.first(where: { $0.position == .front }) ?? devices.first,
            let format = RTCCameraVideoCapturer.supportedFormats(for: device).last,
            let fpsRange = format.videoSupportedFrameRateRanges.first
        else { return }
        capturer.startCapture(with: device, format: format, fps: Int(fpsRange.maxFrameRate))
    }
}
