/*
 * Purpose: Boundary tests for DrillGrader — numeric percent-tolerance, market-
 *          sizing factor bounds (inclusive), and choice-index equality.
 * Inputs: in-memory Drill values with exact tolerance boundaries.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class DrillGraderTests: XCTestCase {
    private func numericPct(value: Double, tolerancePct: Double) -> Drill {
        Drill(key: "k", drillType: .mentalMath, prompt: "p", choices: nil,
              answer: DrillAnswer(kind: .numeric, value: value, tolerancePct: tolerancePct,
                                  toleranceFactor: nil, correctIndex: nil),
              explanation: "e", numbers: [])
    }

    private func sizing(value: Double, factor: Double) -> Drill {
        Drill(key: "k", drillType: .marketSizing, prompt: "p", choices: nil,
              answer: DrillAnswer(kind: .numeric, value: value, tolerancePct: nil,
                                  toleranceFactor: factor, correctIndex: nil),
              explanation: "e", numbers: [])
    }

    private func choice(correctIndex: Int) -> Drill {
        Drill(key: "k", drillType: .frameworkRecall, prompt: "p", choices: ["a", "b", "c"],
              answer: DrillAnswer(kind: .choice, value: nil, tolerancePct: nil,
                                  toleranceFactor: nil, correctIndex: correctIndex),
              explanation: "e", numbers: [])
    }

    // MARK: - numeric percent tolerance

    func testNumericPctExactlyAtTolerancePasses() {
        // value 75, ±2% -> window [73.5, 76.5]; both edges inclusive.
        let drill = numericPct(value: 75, tolerancePct: 2)
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 76.5, choiceIndex: nil))
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 73.5, choiceIndex: nil))
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 75, choiceIndex: nil))
    }

    func testNumericPctOutsideToleranceFails() {
        let drill = numericPct(value: 75, tolerancePct: 2)
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: 76.51, choiceIndex: nil))
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: 73.49, choiceIndex: nil))
    }

    func testNumericMissingInputFails() {
        let drill = numericPct(value: 75, tolerancePct: 2)
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: nil, choiceIndex: nil))
    }

    // MARK: - market-sizing factor bounds (inclusive)

    func testSizingFactorBoundsInclusive() {
        // value 1590, factor 2 -> window [795, 3180]; both edges pass.
        let drill = sizing(value: 1590, factor: 2)
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 795, choiceIndex: nil))
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 3180, choiceIndex: nil))
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: 1590, choiceIndex: nil))
    }

    func testSizingFactorOutsideBoundsFails() {
        let drill = sizing(value: 1590, factor: 2)
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: 794, choiceIndex: nil))
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: 3181, choiceIndex: nil))
    }

    // MARK: - choice

    func testChoiceCorrectIndexPasses() {
        let drill = choice(correctIndex: 1)
        XCTAssertTrue(DrillGrader.grade(drill, numericInput: nil, choiceIndex: 1))
    }

    func testChoiceWrongIndexFails() {
        let drill = choice(correctIndex: 1)
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: nil, choiceIndex: 0))
    }

    func testChoiceMissingInputFails() {
        let drill = choice(correctIndex: 1)
        XCTAssertFalse(DrillGrader.grade(drill, numericInput: nil, choiceIndex: nil))
    }
}
