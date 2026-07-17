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
    // B3 Library aggregates (avg_rating/run_count/done_for_you). Optional so
    // fixtures/back-compat responses without these keys still decode; nil
    // runCount treated as 0 and nil doneForYou as false at the use site.
    let avgRating: Double?
    let runCount: Int?
    let doneForYou: Bool?
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
    // B3 Library aggregates — see CaseSummary for the back-compat rationale.
    let avgRating: Double?
    let runCount: Int?
    let doneForYou: Bool?
}

// B3 GET /api/v1/cases list response: cases + total + the open/done counts
// over the filtered canonical set (drives the retired-done divider/count
// line in F4's Library screen).
struct LibraryPage: Codable, Equatable {
    let cases: [CaseSummary]
    let total: Int
    let openCount: Int
    let doneCount: Int
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

// Free-now availability (Task 9) — AvailabilityStatus/FreeUser moved to
// Shared/AvailabilityModels.swift so the widget extension's ToggleFreeNowIntent
// can decode them too (Task 10).

// B5 GET/PUT /api/v1/profile — school & photo_url read-only from the client's view.
struct ProfileDetail: Codable, Equatable {
    let id: Int
    let email: String
    let displayName: String?
    let bio: String?
    let linkedinUrl: String?
    let school: String?
    let photoUrl: String?
}

// B5 GET/PUT /api/v1/settings/notifications — the five category flags.
struct NotificationSettings: Codable, Equatable {
    var proposals: Bool
    var sessionReminders: Bool
    var feedback: Bool
    var freeNow: Bool
    var community: Bool

    var allEnabled: Bool { proposals && sessionReminders && feedback && freeNow && community }
}
