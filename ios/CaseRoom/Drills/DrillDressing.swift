/*
 * Purpose: Validation for FM prompt dressings — pure string logic with zero
 *          FoundationModels dependency, so it lives ungated and stays testable
 *          on any runtime (the iOS 26+ engine calls it).
 * Inputs: a rewritten prompt string + the drill's `numbers` literals.
 * Outputs: none (pure predicate).
 * Run: DrillDressing.isValid("from 80 to 120?", numbers: ["80", "120"])
 */

import Foundation

enum DrillDressing {
    /// Every string in `numbers` must appear verbatim in `dressed`, else the
    /// dressing is rejected and the plain prompt ships. Substring match (mirrors
    /// the server contract): a reformatted "1,200" fails a "1200" requirement.
    static func isValid(_ dressed: String, numbers: [String]) -> Bool {
        numbers.allSatisfy { dressed.contains($0) }
    }
}
