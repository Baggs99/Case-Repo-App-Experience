/*
 * Purpose: Unit tests for PushCoordinator's pure push-payload route parser.
 * Inputs: none (constructs userInfo dictionaries in-memory).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class PushRouteTests: XCTestCase {
    func testProposalRoutesToProposals() {
        let userInfo: [AnyHashable: Any] = ["kind": "proposal", "proposal_id": 3]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .proposals)
    }

    func testAcceptedRoutesToSession() {
        let userInfo: [AnyHashable: Any] = ["kind": "accepted", "session_id": 7]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .session(7))
    }

    func testKnockRoutesToSession() {
        let userInfo: [AnyHashable: Any] = ["kind": "knock", "session_id": 7]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .session(7))
    }

    func testFeedbackRoutesToSession() {
        let userInfo: [AnyHashable: Any] = ["kind": "feedback", "session_id": 7]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .session(7))
    }

    func testStartingSoonRoutesToSession() {
        let userInfo: [AnyHashable: Any] = ["kind": "starting_soon", "session_id": 7]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .session(7))
    }

    func testSessionIDAsStringDecodes() {
        let userInfo: [AnyHashable: Any] = ["kind": "knock", "session_id": "7"]
        XCTAssertEqual(PushCoordinator.route(from: userInfo), .session(7))
    }

    func testUnknownKindReturnsNil() {
        let userInfo: [AnyHashable: Any] = ["kind": "mystery", "session_id": 7]
        XCTAssertNil(PushCoordinator.route(from: userInfo))
    }

    func testMissingKindReturnsNil() {
        let userInfo: [AnyHashable: Any] = ["session_id": 7]
        XCTAssertNil(PushCoordinator.route(from: userInfo))
    }

    func testMissingSessionIDReturnsNil() {
        let userInfo: [AnyHashable: Any] = ["kind": "knock"]
        XCTAssertNil(PushCoordinator.route(from: userInfo))
    }
}
