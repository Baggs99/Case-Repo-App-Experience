/*
 * Purpose: Verify the color token palettes carry the exact §1 hex values
 *          (owner-locked muted, page, green) in both light and dark takeover.
 * Inputs: DSPalette.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/TokensTests
 */

import XCTest
import SwiftUI
@testable import CaseRoom

final class TokensTests: XCTestCase {
    private func rgb(_ c: Color) -> (Int, Int, Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func testLightPaletteExactHex() {
        XCTAssertTrue(rgb(DSPalette.light.page) == (0xEF, 0xF2, 0xF6))
        XCTAssertTrue(rgb(DSPalette.light.ink) == (0x0D, 0x1C, 0x31))
        XCTAssertTrue(rgb(DSPalette.light.muted) == (0x51, 0x5A, 0x66))     // owner-locked
        XCTAssertTrue(rgb(DSPalette.light.faint) == (0xA9, 0xB4, 0xC4))
        XCTAssertTrue(rgb(DSPalette.light.hairline) == (0xC9, 0xD2, 0xDF))
        XCTAssertTrue(rgb(DSPalette.light.green) == (0x1B, 0x9A, 0x5F))
        XCTAssertTrue(rgb(DSPalette.light.link) == (0x2E, 0x56, 0xC0))
        XCTAssertTrue(rgb(DSPalette.light.surface) == (0xFF, 0xFF, 0xFF))
        XCTAssertFalse(DSPalette.light.isDark)
    }

    func testDarkTakeoverPaletteExactHex() {
        XCTAssertTrue(rgb(DSPalette.dark.page) == (0x08, 0x12, 0x22))
        XCTAssertTrue(rgb(DSPalette.dark.surface) == (0x10, 0x1E, 0x36))
        XCTAssertTrue(rgb(DSPalette.dark.ink) == (0xE9, 0xEE, 0xF5))
        XCTAssertTrue(rgb(DSPalette.dark.muted) == (0x7C, 0x8C, 0xA8))
        XCTAssertTrue(rgb(DSPalette.dark.green) == (0x2F, 0xC0, 0x7E))
        XCTAssertTrue(DSPalette.dark.isDark)
    }
}
