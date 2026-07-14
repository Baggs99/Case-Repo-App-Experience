/*
 * Purpose: Assembles the already-built WebRTC pieces (RTCPeerConnectionWrapper
 *          + WebRTCMediaCapture + Negotiator) behind RemoteMediaControlling so
 *          SessionViewModel can drive a remote session's media without
 *          knowing about WebRTC directly.
 * Inputs: a SignalingChannel + [ICEServer] + polite flag at start(...).
 * Outputs: local camera/mic capture + peer connection side effects; forwards
 *          MediaTransport.onRemoteTrack to onRemoteTrack.
 * Run: consumed by SessionViewModel via the injected makeRemoteMedia factory.
 */

import Foundation

@MainActor
final class RemoteMediaSession: RemoteMediaControlling {
    private var transport: RTCPeerConnectionWrapper?
    private var negotiator: Negotiator?
    private(set) var capture: MediaCapturing?

    var onRemoteTrack: (@MainActor (MediaTrackHandle) -> Void)?

    func start(signaling: SignalingChannel, iceServers: [ICEServer], polite: Bool) async throws {
        guard let wrapper = RTCPeerConnectionWrapper(iceServers: iceServers, forceRelay: false) else {
            throw MediaTransportError.unknown
        }
        let mediaCapture = WebRTCMediaCapture()
        try mediaCapture.start(video: true, audio: true)
        wrapper.addLocalTracks(mediaCapture.localTrackHandles)
        wrapper.onRemoteTrack = { [weak self] handle in
            self?.onRemoteTrack?(handle)
        }

        transport = wrapper
        capture = mediaCapture
        negotiator = Negotiator(transport: wrapper, signaling: signaling, polite: polite)
    }

    func handle(_ message: SignalMessage) async {
        await negotiator?.handle(message)
    }

    func setVideoEnabled(_ enabled: Bool) {
        capture?.setVideoEnabled(enabled)
    }

    func setAudioEnabled(_ enabled: Bool) {
        capture?.setAudioEnabled(enabled)
    }

    func stop() {
        capture?.stop()
        transport?.close()
        capture = nil
        transport = nil
        negotiator = nil
    }
}
