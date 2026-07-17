/*
 * Purpose: Codable models for the B4/B7/B8 Home + Timeline-detail payloads —
 *          dashboard recommendations/diagnostic/timeline, timeline-detail,
 *          gauntlet, and group-board shapes (Task 2, F2 plan).
 * Inputs: JSON decoded by APIClient via JSONDecoder.convertFromSnakeCase.
 * Outputs: none (pure data types).
 * Run: consumed by ios/CaseRoom/Networking/APIClient.swift.
 */

import Foundation

// MARK: - Dashboard additions (B4 §7 / B7 §4)

// dimension_averages item shape confirmed against
// webapp/repositories/dashboard.py:59-91 (dimension_averages) — a flat
// {dimension, avg_score, samples} row, /5-normalized. Decoded only for
// forward-compat; live screens bind to `diagnostic.dimensions` instead.
struct DimensionAverage: Codable, Equatable {
    let dimension: String
    let avgScore: Double
    let samples: Int?
}

// Confirmed against webapp/routes/api_v1.py:372-396 (dashboard) and
// webapp/repositories/dashboard.py:245-282 (recommendations) — key is
// `title`, never `case_title`.
struct Recommendation: Codable, Equatable, Identifiable {
    let caseId: Int
    let title: String
    let caseType: String?
    let difficulty: String?
    let why: String?
    let rule: String?

    var id: Int { caseId }
}

// Same {dimension, avg_score, samples} shape as DimensionAverage, reused for
// diagnostic.dimensions/strengths/weaknesses (dashboard.py:317-339).
struct DimensionScore: Codable, Equatable {
    let dimension: String
    let avgScore: Double
    let samples: Int
}

struct DiagnosticTrend: Codable, Equatable {
    let recentAvg: Double?
    let previousAvg: Double?
    let delta: Double?
    let direction: String?
}

// strengths/weaknesses are dimension-score rows (dims[-2:] / dims[:2] in
// dashboard.py:317-339), NOT plain strings — confirmed against source; this
// is a deviation from the plan's textual [String] sketch (code wins per the
// plan's "Pinned API shapes" header).
struct DiagnosticStats: Codable, Equatable {
    // Named casesDone60D (capital D), not casesDone60d: Foundation's
    // .convertFromSnakeCase maps "cases_done_60d" -> "casesDone60D" (verified
    // directly against JSONDecoder — the digit/letter boundary capitalizes).
    let casesDone60D: Int
    let dimensions: [DimensionScore]
    let strengths: [DimensionScore]
    let weaknesses: [DimensionScore]
    let focusDimension: String?
    let trend: DiagnosticTrend
}

struct NextDeadline: Codable, Equatable {
    let firmId: Int
    let name: String
    let slug: String
    let cycleLabel: String?
    let deadlineDate: String
    let daysRemaining: Int
    let readinessTag: String
}

struct DashboardTimeline: Codable, Equatable {
    let trackedCount: Int
    let nextDeadline: NextDeadline?
}

// MARK: - Timeline detail (B7)

struct TimelineReadiness: Codable, Equatable {
    let label: String
    let ready: Bool
    let focusDimension: String?
    let recentCaseCount: Int
    let threshold: Double
    let minCases: Int
}

struct FirmDeadline: Codable, Equatable {
    let cycleLabel: String?
    let deadlineDate: String
    let region: String?
    let isEstimate: Bool
    let daysRemaining: Int
    let passed: Bool
}

struct FirmPrompt: Codable, Equatable {
    let show: Bool
}

struct TimelineFirmDetail: Codable, Equatable, Identifiable {
    let firmId: Int
    let name: String
    let slug: String
    let status: String
    let addedAt: String?
    let deadline: FirmDeadline?
    let readinessTag: String
    let prompt: FirmPrompt

    var id: Int { firmId }
}

struct TimelineDetail: Codable, Equatable {
    let asOf: String
    let readiness: TimelineReadiness
    let firms: [TimelineFirmDetail]
}

struct FirmCatalogEntry: Codable, Equatable, Identifiable {
    let firmId: Int
    let name: String
    let slug: String
    let tracked: Bool
    let nextDeadline: FirmDeadline?

    var id: Int { firmId }
}

// POST /api/v1/timeline/firms/{id}/result — the four outcome shapes
// (webapp/routes/timeline.py:71-96) share one payload; only the fields for
// the given outcome are present, so all four are optional here.
struct FirmResult: Codable, Equatable {
    let outcome: String
    let status: String?
    let reweight: Reweight?
    let snoozeUntil: String?
    let resultRecordedAt: String?
    let dropped: Bool?
}

struct Reweight: Codable, Equatable {
    // Nullable: readiness.py derives focus_dimension from dims[0] and emits null
    // for a user with no finalized candidate sessions (empty dimension_averages).
    let focusDimension: String?
    let suggestedDrillType: String
    let extraCases: [Int]
}

// MARK: - Gauntlet (B8)

struct GauntletSlot: Codable, Equatable, Identifiable {
    let slot: Int
    let drillType: String
    let key: String
    let prompt: String
    let numbers: [String]
    let choices: [String]?

    var id: Int { slot }
}

struct WeakSection: Codable, Equatable {
    let drillType: String
    let label: String
}

// group_id/name confirmed against webapp/gauntlet.py:61-77 (_group_block) —
// `name` is optional here (guards the `my[0].get("name")` None case) even
// though the group row's name column is normally non-null.
struct GauntletGroup: Codable, Equatable {
    let groupId: Int
    let name: String?
    let rank: Int
    let points: Int
    let pointsBehindNext: Int?
}

struct GauntletResult: Codable, Equatable {
    let score: Double
    let slotsCorrect: Int
    let slots: Int
    let pointsAwarded: Int
    let dailyPercentile: Double?
    let group: GauntletGroup?
    let schoolPercentile: Double?
    let vsPeersDelta: Int?
    let weakSection: WeakSection?
    let streak: Int
    let setKey: String
}

struct Gauntlet: Codable, Equatable {
    let date: String
    let setKey: String
    let provisional: Bool
    let slots: [GauntletSlot]
    let streak: Int
    let submitted: Bool
    let result: GauntletResult?
}

// MARK: - Boards (B8)

// `name` optional: webapp/routes/drills.py:98 sends `grp["name"] if grp else
// None` inside an already-present group object (the race where a resolved
// group id no longer has a row) — guards against a decode crash on that edge.
struct GroupRef: Codable, Equatable {
    let id: Int
    let name: String?
}

struct BoardEntry: Codable, Equatable, Identifiable {
    let userId: Int
    let displayName: String
    let photoKey: String?
    let points: Int
    let rank: Int
    let streak: Int

    var id: Int { userId }
}

struct GroupBoard: Codable, Equatable {
    let scope: String
    let group: GroupRef?
    let entries: [BoardEntry]
}
