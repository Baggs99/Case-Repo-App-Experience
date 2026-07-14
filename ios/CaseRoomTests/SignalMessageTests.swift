/*
 * Purpose: Unit tests for SignalMessage's pure JSON parser and outbound
 *          helpers (no socket involved — the live WS is exercised in Task 15).
 * Inputs: canned JSON strings.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class SignalMessageTests: XCTestCase {

    private func parse(_ json: String) -> SignalMessage? {
        SignalMessage.parse(Data(json.utf8))
    }

    // MARK: - ok

    func testParseOk() {
        let message = parse(#"{"type":"ok","role":"candidate","peer_present":true,"admitted":false}"#)
        XCTAssertEqual(message, .ok(role: "candidate", peerPresent: true, admitted: false))
    }

    func testParseOkMissingFieldFails() {
        let message = parse(#"{"type":"ok","role":"candidate","peer_present":true}"#)
        XCTAssertNil(message)
    }

    // MARK: - knock

    func testParseKnock() {
        let message = parse(#"{"type":"knock","display_name":"Dan"}"#)
        XCTAssertEqual(message, .knock(displayName: "Dan"))
    }

    func testParseKnockMissingDisplayNameFails() {
        let message = parse(#"{"type":"knock"}"#)
        XCTAssertNil(message)
    }

    // MARK: - admit / deny / peer-joined / peer-left / pong

    func testParseAdmit() {
        XCTAssertEqual(parse(#"{"type":"admit"}"#), .admit)
    }

    func testParseDeny() {
        XCTAssertEqual(parse(#"{"type":"deny"}"#), .deny)
    }

    func testParsePeerJoined() {
        XCTAssertEqual(parse(#"{"type":"peer-joined"}"#), .peerJoined)
    }

    func testParsePeerLeft() {
        XCTAssertEqual(parse(#"{"type":"peer-left"}"#), .peerLeft)
    }

    func testParsePong() {
        XCTAssertEqual(parse(#"{"type":"pong"}"#), .pong)
    }

    // MARK: - reveal (exhibit_id as Int or String)

    func testParseRevealWithIntExhibitId() {
        let message = parse(#"{"type":"reveal","exhibit_id":5,"key_b64":"AAAA"}"#)
        XCTAssertEqual(message, .reveal(exhibitId: 5, keyB64: "AAAA"))
    }

    func testParseRevealWithStringExhibitId() {
        let message = parse(#"{"type":"reveal","exhibit_id":"7","key_b64":"AAAA"}"#)
        XCTAssertEqual(message, .reveal(exhibitId: 7, keyB64: "AAAA"))
    }

    func testParseRevealMissingKeyFails() {
        let message = parse(#"{"type":"reveal","exhibit_id":5}"#)
        XCTAssertNil(message)
    }

    func testParseRevealNonNumericStringExhibitIdFails() {
        let message = parse(#"{"type":"reveal","exhibit_id":"not-a-number","key_b64":"AAAA"}"#)
        XCTAssertNil(message)
    }

    // MARK: - session-update

    func testParseSessionUpdate() {
        XCTAssertEqual(parse(#"{"type":"session-update"}"#), .sessionUpdate)
    }

    // MARK: - sdp

    func testParseSDPOffer() {
        let message = parse(#"{"type":"sdp","description":{"type":"offer","sdp":"v=0..."}}"#)
        XCTAssertEqual(message, .sdp(description: SDP(type: "offer", sdp: "v=0...")))
    }

    func testParseSDPAnswer() {
        let message = parse(#"{"type":"sdp","description":{"type":"answer","sdp":"v=0..."}}"#)
        XCTAssertEqual(message, .sdp(description: SDP(type: "answer", sdp: "v=0...")))
    }

    func testParseSDPMissingDescriptionFails() {
        XCTAssertNil(parse(#"{"type":"sdp"}"#))
    }

    func testParseSDPMissingSdpFieldFails() {
        XCTAssertNil(parse(#"{"type":"sdp","description":{"type":"offer"}}"#))
    }

    // MARK: - ice

    func testParseICECandidate() {
        let message = parse(#"{"type":"ice","candidate":{"candidate":"candidate:1 1 UDP...","sdpMid":"0","sdpMLineIndex":0}}"#)
        XCTAssertEqual(message, .ice(candidate: ICECandidate(candidate: "candidate:1 1 UDP...", sdpMid: "0", sdpMLineIndex: 0)))
    }

    func testParseICECandidateWithStringSdpMLineIndex() {
        let message = parse(#"{"type":"ice","candidate":{"candidate":"candidate:1 1 UDP...","sdpMid":"0","sdpMLineIndex":"2"}}"#)
        XCTAssertEqual(message, .ice(candidate: ICECandidate(candidate: "candidate:1 1 UDP...", sdpMid: "0", sdpMLineIndex: 2)))
    }

    func testParseICENullCandidateIsEndOfCandidates() {
        let message = parse(#"{"type":"ice","candidate":null}"#)
        XCTAssertEqual(message, .ice(candidate: nil))
    }

    func testParseICEMissingCandidateKeyFails() {
        XCTAssertNil(parse(#"{"type":"ice"}"#))
    }

    func testParseICECandidateMissingCandidateFieldFails() {
        XCTAssertNil(parse(#"{"type":"ice","candidate":{"sdpMid":"0"}}"#))
    }

    // MARK: - unrecognized / malformed

    func testParseUnrecognizedTypeReturnsUnknown() {
        XCTAssertEqual(parse(#"{"type":"future-thing","payload":"..."}"#), .unknown)
    }

    func testParseMissingTypeFails() {
        XCTAssertNil(parse(#"{"role":"candidate"}"#))
    }

    func testParseMalformedJSONFails() {
        XCTAssertNil(parse("not json at all"))
    }

    func testParseEmptyDataFails() {
        XCTAssertNil(SignalMessage.parse(Data()))
    }

    func testParseNonObjectJSONFails() {
        XCTAssertNil(parse("[1, 2, 3]"))
    }

    // MARK: - outbound helpers

    private func decodeType(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict["type"] as? String
    }

    func testKnockOutboundJSON() {
        let data = SignalMessage.knock()
        XCTAssertEqual(decodeType(data), "knock")
    }

    func testAdmitOutboundJSON() {
        let data = SignalMessage.admit()
        XCTAssertEqual(decodeType(data), "admit")
    }

    func testDenyOutboundJSON() {
        let data = SignalMessage.deny()
        XCTAssertEqual(decodeType(data), "deny")
    }

    func testByeOutboundJSON() {
        let data = SignalMessage.bye()
        XCTAssertEqual(decodeType(data), "bye")
    }

    func testPingOutboundJSON() {
        let data = SignalMessage.ping()
        XCTAssertEqual(decodeType(data), "ping")
    }

    func testSDPOutboundJSON() {
        let data = SignalMessage.sdp(SDP(type: "offer", sdp: "v=0..."))
        XCTAssertEqual(parse(String(decoding: data, as: UTF8.self)), .sdp(description: SDP(type: "offer", sdp: "v=0...")))
    }

    func testICEOutboundJSON() {
        let candidate = ICECandidate(candidate: "candidate:1 1 UDP...", sdpMid: "0", sdpMLineIndex: 0)
        let data = SignalMessage.ice(candidate)
        XCTAssertEqual(parse(String(decoding: data, as: UTF8.self)), .ice(candidate: candidate))
    }

    func testICENilOutboundJSON() {
        let data = SignalMessage.ice(nil)
        XCTAssertEqual(parse(String(decoding: data, as: UTF8.self)), .ice(candidate: nil))
    }

    func testOutboundHelpersNeverProduceSdpOrIce() {
        // These outbound helpers must never emit media-negotiation payloads
        // (sdp/ice are P3-only). Assert the fixed set of "type" values.
        let allowedTypes: Set<String> = ["knock", "admit", "deny", "bye", "ping"]
        let outputs = [
            SignalMessage.knock(), SignalMessage.admit(), SignalMessage.deny(),
            SignalMessage.bye(), SignalMessage.ping(),
        ]
        for data in outputs {
            guard let type = decodeType(data) else {
                XCTFail("missing type")
                continue
            }
            XCTAssertTrue(allowedTypes.contains(type))
        }
    }
}
