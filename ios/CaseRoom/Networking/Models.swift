/*
 * Purpose: Codable models mirroring the /api/v1 JSON contracts (Tasks 6-8).
 * Inputs: JSON decoded by APIClient via JSONDecoder.convertFromSnakeCase.
 * Outputs: none (pure data types).
 * Run: consumed by ios/CaseRoom/Networking/APIClient.swift.
 */

import Foundation

struct User: Codable, Equatable {
    let id: Int
    let email: String
    let name: String
}

struct CaseSummary: Codable, Identifiable, Equatable {
    let id: Int
    let caseTitle: String
    let caseType: String?
    let difficulty: String?
    let difficultyScore: Double?
    let firm: String?
    let industry: String?
    let industryDisplay: String?
    let industryRaw: String?
    let pageCount: Int?
    let sourceSchool: String?
    let sourceYear: Int?
}

struct CaseDetail: Codable, Identifiable, Equatable {
    let id: Int
    let caseTitle: String
    let caseType: String?
    let difficulty: String?
    let difficultyScore: Double?
    let firm: String?
    let industry: String?
    let industryDisplay: String?
    let industryRaw: String?
    let pageCount: Int?
    let sourceSchool: String?
    let sourceYear: Int?
    let previewUrls: [String]
    let pdfUrl: String
}

struct Proposal: Codable, Identifiable, Equatable {
    let id: Int
    let fromName: String
    let fromRole: String
    let caseId: Int
    let caseTitle: String
    let caseType: String?
    let difficulty: String?
    let message: String?
    let proposedTimes: [Date]
    let createdAt: Date
}

struct SessionSummary: Codable, Identifiable, Equatable {
    let id: Int
    let role: String
    let otherUser: String
    let caseTitle: String
    let scheduledAt: Date?
    let state: String?
    let endedAt: Date?
    let grade: Double?
}

struct DashboardStats: Codable, Equatable {
    let sessionsFinalized: Int
    let streakWeeks: Int
    let nextSession: SessionSummary?
    // Added by the P4 drill layer; optional so pre-P4 fixtures/back-compat
    // responses (without these keys) still decode.
    let streakDays: Int?
    let drillDoneToday: Bool?
}

struct AcceptedSession: Codable, Equatable {
    let accepted: Bool
    let sessionId: Int
    let sessionUrl: String
    let icsUrl: String
}

// Free-now availability (Task 9). GET/PUT /api/v1/availability both return this
// shape; `freeUntil` is the caller's own broadcast (null when not free) and
// `others` are classmates currently free. The server coalesces `name` to the
// user's email, so it is never null.
struct AvailabilityStatus: Codable, Equatable {
    let freeUntil: Date?
    let others: [FreeUser]
}

struct FreeUser: Codable, Identifiable, Equatable {
    let userId: Int
    let name: String
    let freeUntil: Date
    var id: Int { userId }
}
