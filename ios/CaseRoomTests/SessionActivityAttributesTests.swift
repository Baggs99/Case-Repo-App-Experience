/*
 * Purpose: Contract guard for SessionActivityAttributes.ContentState — proves
 *          its CodingKeys decode the EXACT snake_case keys the backend push
 *          payload sends (webapp/push/live_activity.py::_content_state),
 *          since ActivityKit decodes pushed content-state with a plain
 *          decoder (no snake_case conversion).
 * Inputs: none (a literal backend-shaped JSON fixture).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class SessionActivityAttributesTests: XCTestCase {
    func testContentStateDecodesBackendShapedJSON() throws {
        let json = """
        {"state":"live","role":"candidate","counterpart_name":"Dana","scheduled_at":null,"started_at":"2026-07-14T12:00:00Z"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SessionActivityAttributes.ContentState.self, from: json)

        XCTAssertEqual(decoded.state, "live")
        XCTAssertEqual(decoded.role, "candidate")
        XCTAssertEqual(decoded.counterpartName, "Dana")
        XCTAssertNil(decoded.scheduledAt)
        XCTAssertEqual(decoded.startedAt, "2026-07-14T12:00:00Z")
    }
}
