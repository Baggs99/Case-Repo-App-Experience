/*
 * Purpose: Smoke test proving the app scaffold builds and the root view initializes.
 * Inputs: none.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class SmokeTests: XCTestCase {
    func testRootTabViewInitializes() {
        _ = RootTabView()
    }
}
