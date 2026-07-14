/*
 * Purpose: Framework-neutral media-transport protocol (for Task 6's
 *          negotiation state machine and its stub, WebRTC-free) plus
 *          RTCPeerConnectionWrapper, the only type in this file that
 *          imports WebRTC and converts neutral <-> RTC* types.
 * Inputs: [ICEServer] (Task 4 model) and a forceRelay debug flag at init;
 *         SDP/ICECandidate values at call sites (mirroring the signaling
 *         WebSocket's {"type":"sdp",...}/{"type":"ice",...} payloads).
 * Outputs: none beyond RTCPeerConnection side effects (offer/answer
 *          generation, ICE gathering, remote-track callbacks).
 * Run: consumed by Task 6 (Negotiator) and Task 7 (capture); see
 *      ios/CaseRoomTests/PeerConnectionTests.swift for config-only coverage.
 */

import WebRTC

// MARK: - Framework-neutral wire/value types

/// An offer/answer as it crosses the signaling WebSocket:
/// {"type":"sdp","description":{"type":"offer"|"answer","sdp":"..."}}.
struct SDP: Equatable {
    let type: String
    let sdp: String
}

/// An ICE candidate as it crosses the signaling WebSocket:
/// {"type":"ice","candidate":{"candidate":...,"sdpMid":...,"sdpMLineIndex":...}}.
struct ICECandidate: Equatable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32?
}

/// Mirrors RTCSignalingState so Task 6's Negotiator can read it for the
/// offer-collision check without importing WebRTC.
enum MediaSignalingState: Equatable {
    case stable
    case haveLocalOffer
    case haveLocalPrAnswer
    case haveRemoteOffer
    case haveRemotePrAnswer
    case closed
}

/// Opaque handle around a local or remote media track. Concrete instances
/// are produced/consumed only by RTCPeerConnectionWrapper (and, later, the
/// capture layer) — the protocol itself never references RTCMediaStreamTrack.
protocol MediaTrackHandle {}

// MARK: - MediaTransport

/// Framework-neutral surface the negotiation state machine (Task 6) depends
/// on, so it (and its test stub) never import WebRTC.
protocol MediaTransport: AnyObject {
    var signalingState: MediaSignalingState { get }
    var onRemoteTrack: (@MainActor (MediaTrackHandle) -> Void)? { get set }
    var onLocalICECandidate: (@MainActor (ICECandidate) -> Void)? { get set }
    var onShouldNegotiate: (@MainActor () -> Void)? { get set }

    func createOffer() async throws -> SDP
    func createAnswer() async throws -> SDP
    func setLocalDescription(_ description: SDP) async throws
    func setRemoteDescription(_ description: SDP) async throws
    func addICECandidate(_ candidate: ICECandidate) async throws
    func addLocalTracks(_ tracks: [MediaTrackHandle])
    func close()
}

// MARK: - RTCPeerConnectionWrapper

final class RTCPeerConnectionWrapper: NSObject, MediaTransport {
    struct TrackHandle: MediaTrackHandle {
        let track: RTCMediaStreamTrack
    }

    private static let factory = RTCPeerConnectionFactory()

    private let peerConnection: RTCPeerConnection

    var onRemoteTrack: (@MainActor (MediaTrackHandle) -> Void)?
    var onLocalICECandidate: (@MainActor (ICECandidate) -> Void)?
    var onShouldNegotiate: (@MainActor () -> Void)?

    var signalingState: MediaSignalingState {
        Self.map(peerConnection.signalingState)
    }

    /// Builds an RTCPeerConnection from the neutral `[ICEServer]` (Task 4's
    /// join-config model), forcing `.relay` transport when `forceRelay` is
    /// set (mirrors rtc.js). Fails (nil) only if the underlying factory
    /// fails to construct a peer connection.
    init?(iceServers: [ICEServer], forceRelay: Bool = false) {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        configuration.iceTransportPolicy = forceRelay ? .relay : .all
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = Self.factory.peerConnection(
            with: configuration, constraints: constraints, delegate: nil
        ) else {
            return nil
        }
        peerConnection = connection
        super.init()
        peerConnection.delegate = self
    }

    func createOffer() async throws -> SDP {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let description = try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? MediaTransportError.unknown)
                }
            }
        }
        return Self.map(description)
    }

    func createAnswer() async throws -> SDP {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let description = try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? MediaTransportError.unknown)
                }
            }
        }
        return Self.map(description)
    }

    func setLocalDescription(_ description: SDP) async throws {
        let rtcDescription = try Self.map(description)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(rtcDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescription(_ description: SDP) async throws {
        let rtcDescription = try Self.map(description)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(rtcDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func addICECandidate(_ candidate: ICECandidate) async throws {
        let rtcCandidate = RTCIceCandidate(
            sdp: candidate.candidate,
            sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
            sdpMid: candidate.sdpMid
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(rtcCandidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func addLocalTracks(_ tracks: [MediaTrackHandle]) {
        for handle in tracks {
            guard let handle = handle as? TrackHandle else { continue }
            peerConnection.add(handle.track, streamIds: ["caseroom"])
        }
    }

    func close() {
        peerConnection.close()
    }

    // MARK: - Neutral <-> RTC* mapping

    private static func map(_ state: RTCSignalingState) -> MediaSignalingState {
        switch state {
        case .stable: return .stable
        case .haveLocalOffer: return .haveLocalOffer
        case .haveLocalPrAnswer: return .haveLocalPrAnswer
        case .haveRemoteOffer: return .haveRemoteOffer
        case .haveRemotePrAnswer: return .haveRemotePrAnswer
        case .closed: return .closed
        @unknown default: return .closed
        }
    }

    private static func map(_ description: RTCSessionDescription) -> SDP {
        SDP(type: Self.string(for: description.type), sdp: description.sdp)
    }

    private static func map(_ description: SDP) throws -> RTCSessionDescription {
        guard let type = Self.sdpType(for: description.type) else {
            throw MediaTransportError.invalidSDPType(description.type)
        }
        return RTCSessionDescription(type: type, sdp: description.sdp)
    }

    private static func string(for type: RTCSdpType) -> String {
        switch type {
        case .offer: return "offer"
        case .prAnswer: return "pranswer"
        case .answer: return "answer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }

    private static func sdpType(for string: String) -> RTCSdpType? {
        switch string {
        case "offer": return .offer
        case "pranswer": return .prAnswer
        case "answer": return .answer
        case "rollback": return .rollback
        default: return nil
        }
    }
}

enum MediaTransportError: Error {
    case unknown
    case invalidSDPType(String)
}

extension RTCPeerConnectionWrapper: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let track = stream.videoTracks.first ?? stream.audioTracks.first else { return }
        let handle = TrackHandle(track: track)
        guard let callback = onRemoteTrack else { return }
        Task { @MainActor in callback(handle) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        guard let callback = onShouldNegotiate else { return }
        Task { @MainActor in callback() }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let neutral = ICECandidate(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        guard let callback = onLocalICECandidate else { return }
        Task { @MainActor in callback(neutral) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
