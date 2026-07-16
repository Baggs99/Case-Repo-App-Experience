/*
 * Purpose: Pure grading of a user's answer against a Drill's DrillAnswer —
 *          percent tolerance (mental_math), factor bounds (market_sizing), and
 *          choice-index equality (framework_recall).
 * Inputs: a Drill plus the user's numericInput and/or choiceIndex.
 * Outputs: Bool correct/incorrect (no side effects).
 * Run: DrillGrader.grade(drill, numericInput: 76.5, choiceIndex: nil)
 */

import Foundation

enum DrillGrader {
    static func grade(_ drill: Drill, numericInput: Double?, choiceIndex: Int?) -> Bool {
        let answer = drill.answer
        switch answer.kind {
        case .numeric:
            guard let input = numericInput, let value = answer.value else { return false }
            // mental_math: within ±tolerancePct of the value.
            if let tolerancePct = answer.tolerancePct {
                return abs(input - value) <= value * tolerancePct / 100
            }
            // market_sizing: within a multiplicative factor either way (inclusive).
            if let factor = answer.toleranceFactor {
                return value / factor <= input && input <= value * factor
            }
            return false
        case .choice:
            guard let choiceIndex = choiceIndex, let correctIndex = answer.correctIndex else { return false }
            return choiceIndex == correctIndex
        }
    }
}
