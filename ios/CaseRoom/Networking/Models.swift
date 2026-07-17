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
    // B4/B7 Home card additions (task 2): additive + optional so the original
    // 5-field decode above still passes against legacy/back-compat payloads
    // that predate these keys. Types defined in HomeModels.swift. Default nil
    // so existing memberwise-init call sites (fixtures/tests) built before
    // this task still compile unchanged.
    let dimensionAverages: [DimensionAverage]?
    let recommendations: [Recommendation]?
    let diagnostic: DiagnosticStats?
    let timeline: DashboardTimeline?

    init(
        sessionsFinalized: Int, streakWeeks: Int, nextSession: SessionSummary?,
        streakDays: Int? = nil, drillDoneToday: Bool? = nil,
        dimensionAverages: [DimensionAverage]? = nil, recommendations: [Recommendation]? = nil,
        diagnostic: DiagnosticStats? = nil, timeline: DashboardTimeline? = nil
    ) {
        self.sessionsFinalized = sessionsFinalized
        self.streakWeeks = streakWeeks
        self.nextSession = nextSession
        self.streakDays = streakDays
        self.drillDoneToday = drillDoneToday
        self.dimensionAverages = dimensionAverages
        self.recommendations = recommendations
        self.diagnostic = diagnostic
        self.timeline = timeline
    }
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
