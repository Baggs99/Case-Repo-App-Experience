/*
 * Purpose: Codable domain models for the daily drill wire contract
 *          (/api/v1/drills/daily) — Drill, DrillType, DrillAnswer, AnswerKind.
 * Inputs: JSON decoded by APIClient's JSONDecoder (.convertFromSnakeCase).
 * Outputs: none (pure value types shared by the grader, engine, and UI).
 * Run: consumed by DrillGrader, ServerDrillEngine, and Task-7 drill views.
 */

import Foundation

enum DrillType: String, Codable {
    case marketSizing = "market_sizing"
    case mentalMath = "mental_math"
    case frameworkRecall = "framework_recall"
}

enum AnswerKind: String, Codable {
    case numeric
    case choice
}

// The graded answer. `.convertFromSnakeCase` maps tolerance_pct/tolerance_factor/
// correct_index onto these fields; exactly one shape is populated per kind
// (numeric+tolerancePct for mental_math, numeric+toleranceFactor for
// market_sizing, choice+correctIndex for framework_recall).
struct DrillAnswer: Codable, Equatable {
    let kind: AnswerKind
    let value: Double?
    let tolerancePct: Double?
    let toleranceFactor: Double?
    let correctIndex: Int?
}

// One rendered drill. `numbers` is every numeric literal in the prompt, verbatim
// as rendered by the server (Task 6's on-device FM validator matches against it —
// do not reformat).
struct Drill: Codable, Equatable {
    let key: String
    let drillType: DrillType
    let prompt: String
    let choices: [String]?
    let answer: DrillAnswer
    let explanation: String
    let numbers: [String]
}
