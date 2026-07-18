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
    // Nil for case-less (negotiating) proposals — B3 allows scheduling before
    // a case is picked. See CaseGateError/negotiation flow (F3).
    let caseId: Int?
    let caseTitle: String?
    let caseType: String?
    let difficulty: String?
    let message: String?
    let proposedTimes: [Date]
    let createdAt: Date
    // F3 additions (Case-Tab contract sheet): direction/state drive the
    // pendingReceived/sentAwaiting buckets; claimToken/counter* only ever
    // populated on the relevant proposal shapes. Defaulted here (and
    // caseId/caseTitle re-defaulted nil) so pre-F3 construction call sites
    // keep compiling unchanged — mirrors DashboardStats's explicit init above.
    let direction: String
    let state: String
    let claimToken: String?
    let counterTimes: [Date]?
    let counterBy: Int?
    let counteredAt: Date?

    init(
        id: Int, fromName: String, fromRole: String, caseId: Int? = nil, caseTitle: String? = nil,
        caseType: String?, difficulty: String?, message: String?, proposedTimes: [Date], createdAt: Date,
        direction: String = "received", state: String = "pending", claimToken: String? = nil,
        counterTimes: [Date]? = nil, counterBy: Int? = nil, counteredAt: Date? = nil
    ) {
        self.id = id
        self.fromName = fromName
        self.fromRole = fromRole
        self.caseId = caseId
        self.caseTitle = caseTitle
        self.caseType = caseType
        self.difficulty = difficulty
        self.message = message
        self.proposedTimes = proposedTimes
        self.createdAt = createdAt
        self.direction = direction
        self.state = state
        self.claimToken = claimToken
        self.counterTimes = counterTimes
        self.counterBy = counterBy
        self.counteredAt = counteredAt
    }
}

// POST /api/proposals/claim/{token} response (F3). convertFromSnakeCase maps
// proposal_id/session_id/needs_negotiation/from_user_id.
struct ClaimResult: Decodable, Equatable {
    let proposalId: Int
    let state: String
    let sessionId: Int?
    let accepted: Bool
    let needsNegotiation: Bool
    let fromUserId: Int
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
    // Omitted by the case-less/negotiating accept shape (B3, contract sheet
    // lines 176-184) — no session_url/ics_url until a case is stamped.
    let sessionUrl: String?
    let icsUrl: String?
}

// GET /api/v1/recaps row (F3, B3 recap gate) — oldest-first, unread-only.
// Identifiable by sessionId: one recap per finalized candidate-seat session.
struct RecapItem: Codable, Equatable, Identifiable {
    let sessionId: Int
    let caseId: Int
    let caseTitle: String
    let interviewerName: String
    let grade: Double?
    let finalizedAt: Date
    let viewedAt: Date?

    var id: Int { sessionId }
}

// Free-now availability (Task 9) — AvailabilityStatus/FreeUser moved to
// Shared/AvailabilityModels.swift so the widget extension's ToggleFreeNowIntent
// can decode them too (Task 10).

// The `school` binding on a profile: a {id, name, domain} object (or null for a
// user with no school_id). Confirmed against webapp/repositories/profile.py:34-42
// and the B5 contract (bgap-b5-plan §Task "get_profile … school = {id,name,domain}
// or None"). It is NOT a bare string — a String? here fails to decode the object
// for any seeded/registered user, which stalls every screen that loads /profile.
struct SchoolRef: Codable, Equatable {
    let id: Int
    let name: String
    let domain: String
}

// B5 GET/PUT /api/v1/profile — school & photo_url read-only from the client's view.
struct ProfileDetail: Codable, Equatable {
    let id: Int
    let email: String
    let displayName: String?
    let bio: String?
    let linkedinUrl: String?
    let school: SchoolRef?
    let photoUrl: String?
}

// POST /api/v1/groups/join (B6, webapp/routes/groups.py:69) row. The route
// returns {id, name, school_id, invite_code, role, already_member}; this
// decodes a deliberate 3-of-6 subset — Swift ignores the unlisted keys, and
// convertFromSnakeCase maps already_member -> alreadyMember.
struct JoinedGroup: Codable, Equatable {
    let id: Int
    let name: String
    let alreadyMember: Bool
}

// Typed onboarding failures the generic APIError can't distinguish: a 404 from
// /groups/join is an unknown invite code (not a routing miss), and OAuth is
// surfaced as unavailable on 503/cancel (see OnboardingOAuth.swift).
enum OnboardingError: Error, Equatable {
    case unknownInviteCode
    case oauthUnavailable
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
