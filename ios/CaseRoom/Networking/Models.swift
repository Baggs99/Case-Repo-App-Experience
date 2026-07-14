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
}

struct AcceptedSession: Codable, Equatable {
    let accepted: Bool
    let sessionId: Int
    let sessionUrl: String
    let icsUrl: String
}
