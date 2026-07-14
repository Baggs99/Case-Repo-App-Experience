/*
 * Purpose: Unit tests for Negotiator's perfect-negotiation state machine —
 *          the offer/collision/rollback/ice logic ported from rtc.js's
 *          onnegotiationneeded + handleSignal, driven with a stub
 *          MediaTransport + stub SignalingChannel (no WebRTC, no socket).
 * Inputs: none (in-memory stub transport/signaling).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CaseRoomTests/NegotiatorTests
 */

import XCTest
@testable import CaseRoom

private final class NegotiatorStubTransport: MediaTransport {
    var signalingState: MediaSignalingState = .stable
    var onRemoteTrack: ((MediaTrackHandle) -> Void)?
    var onLocalICECandidate: ((ICECandidate) -> Void)?
    var onShouldNegotiate: (() -> Void)?

    var offerToReturn = SDP(type: "offer", sdp: "offer-sdp")
    var answerToReturn = SDP(type: "answer", sdp: "answer-sdp")
    var addICECandidateError: Error?

    private(set) var createOfferCallCount = 0
    private(set) var createAnswerCallCount = 0
    private(set) var setLocalDescriptionCalls: [SDP] = []
    private(set) var setRemoteDescriptionCalls: [SDP] = []
    private(set) var addICECandidateCalls: [ICECandidate] = []

    func createOffer() async throws -> SDP {
        createOfferCallCount += 1
        return offerToReturn
    }

    func createAnswer() async throws -> SDP {
        createAnswerCallCount += 1
        return answerToReturn
    }

    func setLocalDescription(_ description: SDP) async throws {
        setLocalDescriptionCalls.append(description)
    }

    func setRemoteDescription(_ description: SDP) async throws {
        setRemoteDescriptionCalls.append(description)
    }

    func addICECandidate(_ candidate: ICECandidate) async throws {
        addICECandidateCalls.append(candidate)
        if let addICECandidateError {
            throw addICECandidateError
        }
    }

    func addLocalTracks(_ tracks: [MediaTrackHandle]) {}

    func close() {}
}

private struct NegotiatorStubError: Error {}

private final class NegotiatorStubSignaling: SignalingChannel {
    private(set) var sentSDP: [SDP] = []
    private(set) var sentICE: [ICECandidate?] = []

    func connect(sessionId: Int) async -> AsyncStream<SignalMessage> {
        AsyncStream { continuation in continuation.finish() }
    }

    func send(_ data: Data) async {}
    func disconnect() async {}

    func sendSDP(_ description: SDP) {
        sentSDP.append(description)
    }

    func sendICE(_ candidate: ICECandidate?) {
        sentICE.append(candidate)
    }
}

final class NegotiatorTests: XCTestCase {

    // MARK: - onShouldNegotiate (impolite side offers)

    @MainActor
    func testImpoliteFiresOfferOnShouldNegotiate() async {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        transport.onShouldNegotiate?()
        // negotiationNeeded() runs on a detached Task off this closure —
        // give the run loop a turn to complete it.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(transport.createOfferCallCount, 1)
        XCTAssertEqual(transport.setLocalDescriptionCalls, [transport.offerToReturn])
        XCTAssertEqual(signaling.sentSDP, [transport.offerToReturn])
        _ = negotiator // keep alive through the assertions above
    }

    // MARK: - collision: impolite side ignores a colliding offer

    @MainActor
    func testImpoliteCollidingOfferIsIgnored() async {
        let transport = NegotiatorStubTransport()
        transport.signalingState = .haveLocalOffer // simulates makingOffer in flight
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        await negotiator.handle(.sdp(description: SDP(type: "offer", sdp: "remote-offer")))

        XCTAssertTrue(negotiator.ignoreOffer)
        XCTAssertTrue(transport.setRemoteDescriptionCalls.isEmpty)
        XCTAssertTrue(signaling.sentSDP.isEmpty)
    }

    // MARK: - collision: polite side accepts (rollback) and answers

    @MainActor
    func testPoliteCollidingOfferRollsBackAndAnswers() async {
        let transport = NegotiatorStubTransport()
        transport.signalingState = .haveLocalOffer
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: true)

        let incoming = SDP(type: "offer", sdp: "remote-offer")
        await negotiator.handle(.sdp(description: incoming))

        XCTAssertFalse(negotiator.ignoreOffer)
        XCTAssertEqual(transport.setRemoteDescriptionCalls, [incoming])
        XCTAssertEqual(transport.createAnswerCallCount, 1)
        XCTAssertEqual(transport.setLocalDescriptionCalls, [transport.answerToReturn])
        XCTAssertEqual(signaling.sentSDP, [transport.answerToReturn])
    }

    // MARK: - non-colliding offer (stable state) is always applied

    @MainActor
    func testNonCollidingOfferIsAppliedByImpoliteSide() async {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        let incoming = SDP(type: "offer", sdp: "remote-offer")
        await negotiator.handle(.sdp(description: incoming))

        XCTAssertFalse(negotiator.ignoreOffer)
        XCTAssertEqual(transport.setRemoteDescriptionCalls, [incoming])
        XCTAssertEqual(transport.createAnswerCallCount, 1)
        XCTAssertEqual(signaling.sentSDP, [transport.answerToReturn])
    }

    // MARK: - answer is applied without generating a further answer

    @MainActor
    func testInboundAnswerIsAppliedWithoutFurtherAnswer() async {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        let incoming = SDP(type: "answer", sdp: "remote-answer")
        await negotiator.handle(.sdp(description: incoming))

        XCTAssertEqual(transport.setRemoteDescriptionCalls, [incoming])
        XCTAssertEqual(transport.createAnswerCallCount, 0)
        XCTAssertTrue(signaling.sentSDP.isEmpty)
    }

    // MARK: - onLocalICECandidate forwards to signaling

    @MainActor
    func testLocalICECandidateIsForwardedToSignaling() {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        let candidate = ICECandidate(candidate: "candidate:1", sdpMid: "0", sdpMLineIndex: 0)
        transport.onLocalICECandidate?(candidate)

        XCTAssertEqual(signaling.sentICE, [candidate])
        _ = negotiator // keep alive through the assertion above
    }

    // MARK: - inbound ice

    @MainActor
    func testInboundICEIsAddedToTransport() async {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        let candidate = ICECandidate(candidate: "candidate:1", sdpMid: "0", sdpMLineIndex: 0)
        await negotiator.handle(.ice(candidate: candidate))

        XCTAssertEqual(transport.addICECandidateCalls, [candidate])
    }

    @MainActor
    func testInboundNilICEIsNotAddedToTransport() async {
        let transport = NegotiatorStubTransport()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        await negotiator.handle(.ice(candidate: nil))

        XCTAssertTrue(transport.addICECandidateCalls.isEmpty)
    }

    // MARK: - ice errors are swallowed while ignoreOffer, not otherwise

    @MainActor
    func testICEErrorIsSwallowedWhileIgnoringOffer() async {
        let transport = NegotiatorStubTransport()
        transport.signalingState = .haveLocalOffer
        transport.addICECandidateError = NegotiatorStubError()
        let signaling = NegotiatorStubSignaling()
        let negotiator = Negotiator(transport: transport, signaling: signaling, polite: false)

        // Force ignoreOffer = true via an impolite colliding offer.
        await negotiator.handle(.sdp(description: SDP(type: "offer", sdp: "remote-offer")))
        XCTAssertTrue(negotiator.ignoreOffer)

        let candidate = ICECandidate(candidate: "candidate:1", sdpMid: "0", sdpMLineIndex: 0)
        // Must not throw/crash even though addICECandidate throws.
        await negotiator.handle(.ice(candidate: candidate))

        XCTAssertEqual(transport.addICECandidateCalls, [candidate])
    }
}
