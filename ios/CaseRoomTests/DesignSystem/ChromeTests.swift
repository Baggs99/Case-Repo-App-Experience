/*
 * Purpose: Verify the tab slot order/labels and that all chrome views build.
 * Inputs: DSTab, DSTabBar, WordmarkChip, AvatarPill, BackPill, DSToast, DSBackground.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/ChromeTests
 */

import XCTest
import SwiftUI
@testable import CaseRoom

final class ChromeTests: XCTestCase {
    func testTabLabelsMatchDesign() {
        XCTAssertEqual(DSTab.allCases.map(\.label),
                       ["HOME", "LIBRARY", "CASE", "COMMUNITY", "DRILLS"])
    }

    func testChromeViewsBuild() {
        _ = AnyView(WordmarkChip())
        _ = AnyView(AvatarPill(initials: "AO"))
        _ = AnyView(BackPill(label: "Community", context: "GROUP"))
        _ = AnyView(DSTabBar(selection: .constant(.home)))
        _ = AnyView(DSTabBar(selection: .constant(.caseTab)))
        _ = AnyView(DSToast(text: "Copied"))
        _ = AnyView(DSBackground())
        _ = AnyView(Color.clear.dsHeaderFade())
    }
}
