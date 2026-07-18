/*
 * Purpose: Unit tests for PasscodeKeypad.apply — the pure key rule behind the
 *          keypad: digits append up to 6, a 7th is ignored, ⌫ removes the last,
 *          and `completed` is true exactly on the 5→6 transition (auto-advance).
 * Inputs: none (pure static helper).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class PasscodeKeypadTests: XCTestCase {
    func testAppendsUpToSix() {
        var code = ""
        for digit in ["1", "2", "3", "4", "5", "6"] {
            code = PasscodeKeypad.apply(key: digit, to: code).code
        }
        XCTAssertEqual(code, "123456")
    }

    func testIgnoresSeventhDigit() {
        let result = PasscodeKeypad.apply(key: "7", to: "123456")
        XCTAssertEqual(result.code, "123456")
        XCTAssertFalse(result.completed)
    }

    func testDeleteRemovesLast() {
        XCTAssertEqual(PasscodeKeypad.apply(key: "⌫", to: "123").code, "12")
    }

    func testDeleteOnEmptyIsNoOp() {
        let result = PasscodeKeypad.apply(key: "⌫", to: "")
        XCTAssertEqual(result.code, "")
        XCTAssertFalse(result.completed)
    }

    func testCompletedFiresExactlyAtSix() {
        XCTAssertFalse(PasscodeKeypad.apply(key: "5", to: "1234").completed)   // → 5 digits
        XCTAssertTrue(PasscodeKeypad.apply(key: "6", to: "12345").completed)   // → 6th lands
        XCTAssertFalse(PasscodeKeypad.apply(key: "7", to: "123456").completed) // capped, no re-fire
        XCTAssertFalse(PasscodeKeypad.apply(key: "⌫", to: "123456").completed) // delete never completes
    }

    func testIgnoresNonDigitKeys() {
        XCTAssertEqual(PasscodeKeypad.apply(key: "a", to: "12").code, "12")
        XCTAssertEqual(PasscodeKeypad.apply(key: ".", to: "12").code, "12")
    }
}
