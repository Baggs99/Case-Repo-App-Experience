/*
 * Purpose: Codable models for the F8 Community payloads (B6 report, pinned
 *          shapes) — connections, groups (summary/detail/members/leaderboard),
 *          admin-only group progress, and school standing.
 * Inputs: JSON decoded by APIClient via JSONDecoder.convertFromSnakeCase.
 * Outputs: none (pure data types).
 * Run: consumed by ios/CaseRoom/Networking/APIClient.swift.
 */

import Foundation

// GET /api/v1/connections -> {connections:[…]}. Accepted connections only;
// free_now is joined from availability, swap_invite_pending is LIVE on this
// branch (B3 merged) — both are the source of the CONNECTIONS row decorations
// (NOT the /availability endpoint).
struct Connection: Codable, Equatable, Identifiable {
    let userId: Int
    let displayName: String
    let photoUrl: String?
    let bio: String?
    let freeNow: Bool
    let swapInvitePending: Bool

    var id: Int { userId }
}

// GET /api/v1/groups -> {groups:[…]}; also the shape of the POST /groups
// creation response (creator role is always "admin"). role: "admin"|"member".
struct GroupSummary: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let schoolId: Int?
    let inviteCode: String
    let role: String
}

// The `group` object inside GET /api/v1/groups/{id} — no role (that's
// derived from `members[]` per the pinned isAdmin rule, not carried here).
struct GroupInfo: Codable, Equatable {
    let id: Int
    let name: String
    let schoolId: Int?
    let inviteCode: String
}

struct GroupMember: Codable, Equatable, Identifiable {
    let userId: Int
    let displayName: String
    let photoUrl: String?
    let role: String

    var id: Int { userId }
}

struct GroupLeaderboardEntry: Codable, Equatable, Identifiable {
    let userId: Int
    let displayName: String
    let photoUrl: String?
    let points: Int
    let rank: Int
    let streak: Int

    var id: Int { userId }
}

// GET /api/v1/groups/{id} (member-only; 404 non-member) — webapp/routes/
// groups.py:90-102. isAdmin is derived by the VM: my row in `members` has
// role == "admin" (deterministic; group itself carries no role).
struct GroupDetail: Codable, Equatable {
    let group: GroupInfo
    let members: [GroupMember]
    let leaderboard: [GroupLeaderboardEntry]
}

// GET /api/v1/groups/{id}/progress (admin-only; 403 member) member row —
// mean_grade is nullable (a member with no finalized candidate sessions).
struct GroupProgressMember: Codable, Equatable, Identifiable {
    let userId: Int
    let displayName: String
    let casesDone: Int
    let meanGrade: Double?
    // "drill_attempts_30d" -> convertFromSnakeCase capitalizes the trailing
    // letter at the digit boundary ("30d" -> "30D"), same rule verified for
    // DiagnosticStats.casesDone60D in HomeModels.swift.
    let drillAttempts30D: Int
    let streak: Int

    var id: Int { userId }
}

// The school object inside GET /api/v1/leaderboards/school — always present
// when `school` is non-null (own school_id/name/campus_city/avg pctl/rank).
struct SchoolInfo: Codable, Equatable {
    let schoolId: Int
    let name: String
    let campusCity: String
    let avgMemberPercentile: Double
    let rank: Int
}

// GET /api/v1/leaderboards/school -> {school:{…}|null, your_percentile:float|null}.
// `school` is null in dev seed data — the hero renders a muted "No standing
// yet" line in that case, never a fabricated count (Decisions §0.2).
struct SchoolStanding: Codable, Equatable {
    let school: SchoolInfo?
    let yourPercentile: Double?
}
