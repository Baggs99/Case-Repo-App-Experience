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
            // mental_math: within ±tolerancePct of the value. abs(value) so a
            // negative reference (e.g. mm_pct_change with b<a) still yields a
            // positive tolerance window instead of grading nothing correct.
            if let tolerancePct = answer.tolerancePct {
                return abs(input - value) <= abs(value) * tolerancePct / 100
            }
            // market_sizing: within a multiplicative factor either way (inclusive).
            // value/factor and value*factor swap order when value is negative, so
            // normalize to [lo, hi] rather than assume value/factor is the lower.
            if let factor = answer.toleranceFactor {
                let lo = min(value / factor, value * factor)
                let hi = max(value / factor, value * factor)
                return input >= lo && input <= hi
            }
            return false
        case .choice:
            guard let choiceIndex = choiceIndex, let correctIndex = answer.correctIndex else { return false }
            return choiceIndex == correctIndex
        }
    }
}
