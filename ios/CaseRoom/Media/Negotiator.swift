/*
 * Purpose: Perfect-negotiation state machine (RFC 8829), byte-for-byte
 *          mirroring webapp/static/js/caseroom/rtc.js's onnegotiationneeded
 *          and handleSignal — resolves offer collisions by polite/impolite
 *          role and forwards local/remote sdp+ice over the signaling
 *          channel, framework-neutral (depends only on MediaTransport).
 * Inputs: a MediaTransport (Task 5's RTCPeerConnectionWrapper or a test
 *         stub), a SignalingChannel to send sdp/ice frames, and the
 *         session's polite flag (candidate = polite, interviewer = impolite,
 *         per spec §4.3).
 * Outputs: sdp/ice frames sent via signaling; transport local/remote
 *          description + ICE candidate calls as side effects.
 * Run: let negotiator = Negotiator(transport: transport, signaling: signaling, polite: polite)
 *      // then feed inbound signaling: await negotiator.handle(message)
 */

import Foundation

@MainActor
final class Negotiator {
    private let transport: MediaTransport
    private let signaling: SignalingChannel
    private let polite: Bool

    private(set) var makingOffer = false
    private(set) var ignoreOffer = false

    init(transport: MediaTransport, signaling: SignalingChannel, polite: Bool) {
        self.transport = transport
        self.signaling = signaling
        self.polite = polite

        transport.onShouldNegotiate = { [weak self] in
            Task { await self?.negotiationNeeded() }
        }
        transport.onLocalICECandidate = { [weak self] candidate in
            self?.signaling.sendICE(candidate)
        }
    }

    /// Entry point for the session layer (Task 8): feed every inbound
    /// sdp/ice signaling message here.
    func handle(_ message: SignalMessage) async {
        switch message {
        case .sdp(let description):
            await handleSDP(description)
        case .ice(let candidate):
            await handleICE(candidate)
        default:
            break
        }
    }

    /// Mirrors rtc.js's pc.onnegotiationneeded.
    private func negotiationNeeded() async {
        makingOffer = true
        defer { makingOffer = false }
        do {
            let offer = try await transport.createOffer()
            try await transport.setLocalDescription(offer)
            signaling.sendSDP(offer)
        } catch {
            print("Negotiator: negotiation failed: \(error)")
        }
    }

    /// Mirrors rtc.js's handleSignal sdp branch.
    ///
    /// KNOWN REAL-DEVICE RISK: the polite side's rollback here is implicit —
    /// setRemoteDescription(offer) during a collision relies on native
    /// libwebrtc supporting implicit rollback the way browsers do. If the
    /// native SDK rejects this on a real device, an explicit rollback may be
    /// needed (Task 12 real-device check); not addressed here.
    private func handleSDP(_ incoming: SDP) async {
        let collision = incoming.type == "offer"
            && (makingOffer || transport.signalingState != .stable)
        ignoreOffer = !polite && collision
        if ignoreOffer { return }

        do {
            try await transport.setRemoteDescription(incoming) // implicit rollback when polite
            if incoming.type == "offer" {
                let answer = try await transport.createAnswer()
                try await transport.setLocalDescription(answer)
                signaling.sendSDP(answer)
            }
        } catch {
            print("Negotiator: handleSDP failed: \(error)")
        }
    }

    /// Mirrors rtc.js's handleSignal ice branch. The web peer's
    /// end-of-candidates null is dropped — native WebRTC doesn't need it.
    private func handleICE(_ candidate: ICECandidate?) async {
        guard let candidate else { return }
        do {
            try await transport.addICECandidate(candidate)
        } catch {
            if !ignoreOffer {
                print("Negotiator: addICECandidate failed: \(error)")
            }
        }
    }
}
