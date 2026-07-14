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

    // MARK: - unrecognized / malformed

    func testParseUnrecognizedTypeReturnsUnknown() {
        XCTAssertEqual(parse(#"{"type":"sdp","sdp":"..."}"#), .unknown)
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
