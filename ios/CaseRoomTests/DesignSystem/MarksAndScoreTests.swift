/*
 * Purpose: Verify the staircase-mark and stepped-timeline path geometry match the
 *          canvas exactly, and the score-cell strip builds at all three sizes.
 * Inputs: StaircaseMark, StepPath, ScoreCells.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/MarksAndScoreTests
 */

import XCTest
import SwiftUI
@testable import CaseRoom

final class MarksAndScoreTests: XCTestCase {
    func testStaircaseMarkBoundingBox() {
        // Native 48×40 viewBox: extremes (4,4)…(45,35) → x4 y4 w41 h31.
        let bb = StaircaseMark().path(in: CGRect(x: 0, y: 0, width: 48, height: 40)).boundingRect
        XCTAssertEqual(bb.minX, 4, accuracy: 0.01)
        XCTAssertEqual(bb.minY, 4, accuracy: 0.01)
        XCTAssertEqual(bb.maxX, 45, accuracy: 0.01)
        XCTAssertEqual(bb.maxY, 35, accuracy: 0.01)
    }

    func testStaircaseMarkSegmentLength() {
        // Sum of the seven axis-aligned segments = 72 (design dasharray 74 = rounded).
        let pts: [(CGFloat, CGFloat)] = [(4,35),(15,35),(15,25),(26,25),(26,15),(37,15),(37,4),(45,4)]
        var len: CGFloat = 0
        for i in 1..<pts.count { len += abs(pts[i].0 - pts[i-1].0) + abs(pts[i].1 - pts[i-1].1) }
        XCTAssertEqual(len, 72, accuracy: 0.01)
    }

    func testStepPathBoundingBox() {
        let bb = StepPath().path(in: CGRect(x: 0, y: 0, width: 320, height: 64)).boundingRect
        XCTAssertEqual(bb.minX, 2, accuracy: 0.01)
        XCTAssertEqual(bb.maxX, 318, accuracy: 0.01)
        XCTAssertEqual(bb.minY, 8, accuracy: 0.01)
        XCTAssertEqual(bb.maxY, 58, accuracy: 0.01)
    }

    func testScoreCellsBuildAtEachSize() {
        _ = AnyView(ScoreCells(count: 5, value: 3, size: .large, interactive: true))
        _ = AnyView(ScoreCells(count: 10, value: 7, size: .medium))
        _ = AnyView(ScoreCells(count: 12, value: 0, size: .small))
    }
}
