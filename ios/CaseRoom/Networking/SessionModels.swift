/*
 * Purpose: Codable models mirroring the /api/practice JSON contracts (Task 7).
 * Inputs: JSON decoded by APIClient via JSONDecoder.convertFromSnakeCase.
 * Outputs: none (pure data types).
 * Run: consumed by ios/CaseRoom/Networking/APIClient.swift SessionService methods.
 */

import Foundation

struct SessionDetail: Codable, Identifiable, Equatable {
    let id: Int
    let interviewerId: Int
    let candidateId: Int
    let caseId: Int
    let state: String
    let mode: String
    let consentInterviewer: Bool
    let consentCandidate: Bool
    let scheduledAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    // Present on GET /api/practice/{id} (joined names + role); absent from
    // the bare session row returned by /consent and /state.
    let interviewerName: String?
    let candidateName: String?
    let caseTitle: String?
    let yourRole: String?
}

struct ExhibitMeta: Codable, Equatable {
    let exhibitId: Int
    let idx: Int
    let sourcePages: String
    let width: Int
    let height: Int
    let bytes: Int
    let ivB64: String
}

struct RubricTemplateItem: Codable, Equatable {
    let id: String
    let label: String
    let dimension: String
    let maxPoints: Int
}

struct RubricItemScore: Codable, Equatable {
    let points: Int
    let note: String
}

struct RubricState: Codable, Equatable {
    let templateItems: [RubricTemplateItem]
    let items: [String: RubricItemScore]
    let notesMd: String
    let gradePreview: Double
    let grade: Double?
    let finalizedAt: Date?
}

struct Finalized: Codable, Equatable {
    let grade: Double
    let finalizedAt: Date
    // MARK: - F5 debrief seeding (B3 §7.3) — additive + optional so pre-F5
    // fixtures/tests (and the finalize response before these keys existed) still
    // decode. Explicit init keeps existing Finalized(grade:finalizedAt:) call
    // sites compiling; Codable synthesis is unaffected.
    let nextRecommendation: Recommendation?
    let prefillProposal: FinalizePrefill?

    init(grade: Double, finalizedAt: Date,
         nextRecommendation: Recommendation? = nil, prefillProposal: FinalizePrefill? = nil) {
        self.grade = grade
        self.finalizedAt = finalizedAt
        self.nextRecommendation = nextRecommendation
        self.prefillProposal = prefillProposal
    }
}

// POST /api/practice/pair/create response (Task 14).
struct PairToken: Codable, Equatable {
    let token: String
    let expiresAt: Date
}

// GET /api/practice/{id}/join-config response (Task 4). SessionDetail.mode
// (not a JoinConfig field) is what callers use to gate media on remote-mode.
struct JoinConfig: Codable, Equatable {
    let sessionId: Int
    let yourRole: String
    let wsPath: String
    let iceServers: [ICEServer]
}

struct ICEServer: Codable, Equatable {
    let urls: [String]
    let username: String?
    let credential: String?
}
