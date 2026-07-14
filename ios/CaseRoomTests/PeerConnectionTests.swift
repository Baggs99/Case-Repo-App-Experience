/*
 * Purpose: Config-only unit tests for RTCPeerConnectionWrapper — asserts it
 *          initializes with neutral ICE server config. No camera/live media
 *          (that's Task 12 real-device); construction + config only.
 * Inputs: none.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CaseRoomTests/PeerConnectionTests
 */

import XCTest
@testable import CaseRoom

final class PeerConnectionTests: XCTestCase {
    func testInitializesWithSTUNAndTURNServers() {
        let servers = [
            ICEServer(urls: ["stun:stun.example.com:19302"], username: nil, credential: nil),
            ICEServer(urls: ["turn:turn.example.com:3478"], username: "user", credential: "pass"),
        ]

        let wrapper = RTCPeerConnectionWrapper(iceServers: servers)

        XCTAssertNotNil(wrapper)
        XCTAssertEqual(wrapper?.signalingState, .stable)
    }

    func testInitializesWithForceRelay() {
        let servers = [ICEServer(urls: ["turn:turn.example.com:3478"], username: "user", credential: "pass")]

        let wrapper = RTCPeerConnectionWrapper(iceServers: servers, forceRelay: true)

        XCTAssertNotNil(wrapper)
        XCTAssertEqual(wrapper?.signalingState, .stable)
    }

    func testInitializesWithNoICEServers() {
        let wrapper = RTCPeerConnectionWrapper(iceServers: [])

        XCTAssertNotNil(wrapper)
    }
}
