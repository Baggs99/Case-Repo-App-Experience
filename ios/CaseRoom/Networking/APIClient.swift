/*
 * Purpose: Talks to the CaseRoom /api/v1 and /api/practice endpoints over
 *          cookie-session auth.
 * Inputs: Info.plist key API_BASE_URL (falls back to localhost:8077 for sim).
 * Outputs: none (network side effects only); cookies persist via the App
 *          Group's shared cookie store (AppGroup.makeURLSessionConfiguration),
 *          shared with the widget extension.
 * Run: APIClient.shared.login(email:password:) etc., from SessionStore.
 */

import Foundation

enum APIError: Error {
    case unauthorized
    case server(Int)
    case decoding(Error)
    case transport(Error)
}

// Thrown by submitGauntlet when the server returns 409 {"error":
// "already_submitted", ...} — B8 allows one gauntlet submission per user per
// day. The VM recovers by re-fetching gauntlet() and showing its embedded
// (already-scored) `result`.
enum GauntletError: Error, Equatable {
    case alreadySubmitted
}

// Thrown by acceptProposal/claimProposal/pairClaim when the server returns
// 409 {"detail": {"blocked_by_recap": session_id}} (B3) — the caller is a
// gated candidate who must close an unread recap before scheduling further.
// Never returned for interviewer seats, drills, or browsing (contract sheet
// "409 Conflict Responses"). Swap/accept is F5's territory — not wired here.
enum CaseGateError: Error, Equatable {
    case blockedByRecap(Int)
}

// Thrown by uploadRecordingChunk when the server rejects a chunk with
// 409 {"detail": "expected seq N"} — the client is out of sync and must
// resend starting at N (RecordingUploader does this resync).
enum RecordingChunkError: Error, Equatable {
    case seqMismatch(expected: Int)
    /// Server repeated the same `expected` seq with no forward progress —
    /// resuming would loop forever, so RecordingUploader gives up.
    case stalled(seq: Int)
    /// Server's `expected` seq is past the end of the chunk list — a
    /// malformed resync that would otherwise silently truncate the upload.
    case invalidExpectedSeq(expected: Int)
}

// Covers the /api/practice/pair/* endpoints (Task 14): interviewer mints a
// token (pairCreate) and polls for the session it creates (pairStatus);
// candidate claims it (pairClaim), which creates the session.
protocol PairService {
    func pairCreate(caseId: Int) async throws -> PairToken
    func pairStatus(token: String) async throws -> Int?
    func pairClaim(token: String) async throws -> Int
}

// Free-now availability (Task 9). GET/PUT/DELETE /api/v1/availability, all
// cookie-authed same-origin from the native client.
protocol AvailabilityService {
    func availability() async throws -> AvailabilityStatus
    func setFree(minutes: Int) async throws -> AvailabilityStatus
    func clearFree() async throws
}

// Profile + notification settings (B5). All cookie-authed; PUT/POST are
// same-origin from the native client.
protocol ProfileService {
    func profile() async throws -> ProfileDetail
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String
    func notificationSettings() async throws -> NotificationSettings
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings
}

// Firm tracking + timeline-detail (B7 §4, Task 2). All cookie-authed;
// POST/DELETE are same-origin from the native client, no Origin header needed.
protocol TimelineService {
    func timeline() async throws -> TimelineDetail
    func timelineFirms() async throws -> [FirmCatalogEntry]
    func trackFirm(firmId: Int) async throws
    func untrackFirm(firmId: Int) async throws
    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult
}

// "Next up for you" (B4 §7, Task 2). Swap re-calls with the shown id excluded.
protocol RecommendationService {
    func recommendations(exclude: [Int]) async throws -> [Recommendation]
}

// Today's global gauntlet set + percentile-first results (B8, Task 2); the
// scored submission + trends (B8, F7 Task 1).
protocol GauntletService {
    func gauntlet() async throws -> Gauntlet
    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult
    func trends() async throws -> GauntletTrends
}

// Scoped leaderboards; Home's cohort footer only ever asks for scope=group,
// the one scope with literal rank/points (B8, Task 2). F7 Task 1 adds the
// remaining three scopes for the Drills hub's board switcher.
protocol BoardService {
    func groupBoard() async throws -> GroupBoard
    func schoolBoard() async throws -> SchoolBoard
    func globalBoard() async throws -> GlobalBoard
    func schoolsBoard() async throws -> SchoolsBoard
}

// Community tab (F8, Task 1): connections + groups + school standing. All
// cookie-authed; POST/PUT are same-origin from the native client.
protocol CommunityService {
    func connections() async throws -> [Connection]
    func groups() async throws -> [GroupSummary]
    func createGroup(name: String) async throws -> GroupSummary
    func group(id: Int) async throws -> GroupDetail
    func transferGroupAdmin(id: Int, userId: Int) async throws
    func groupProgress(id: Int) async throws -> [GroupProgressMember]
    func schoolStanding() async throws -> SchoolStanding
}

struct CaseQuery {
    var q: String?
    var difficulty: String?
    var industry: String?
    var caseType: String?
    var school: String?
    var limit: Int?
}

// Covers the existing /api/practice/* endpoints (Task 7). All cookie-authed;
// POST/PUT are same-origin from the native client, no Origin header needed.
protocol SessionService {
    func sessionDetail(id: Int) async throws -> SessionDetail
    func joinConfig(id: Int) async throws -> JoinConfig
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail
    func transition(id: Int, target: String) async throws -> SessionDetail
    func rubric(id: Int) async throws -> RubricState
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double
    func reveal(id: Int, exhibitId: Int) async throws
    func exhibits(id: Int) async throws -> [ExhibitMeta]
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws
    func completeRecording(id: Int) async throws
    func finalize(id: Int, grade: Double?) async throws -> Finalized
}

actor APIClient: SessionService, PairService, DrillService, AvailabilityService, ProfileService,
    TimelineService, RecommendationService, GauntletService, BoardService, CommunityService {
    static let shared = APIClient()

    // Immutable and Sendable, so safe to read from outside actor isolation
    // (e.g. resolving relative preview/PDF URLs from a SwiftUI view).
    nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = URLSession(configuration: AppGroup.makeURLSessionConfiguration())) {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: configured) {
            self.baseURL = url
        } else {
            self.baseURL = URL(string: "http://127.0.0.1:8077")!
        }
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = APIClient.fractionalFormatter.date(from: string) {
                return date
            }
            if let date = APIClient.plainFormatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date string, got \(string)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIClient.plainFormatter.string(from: date))
        }
        self.encoder = encoder
    }

    // Postgres timestamptz can serialize with or without fractional seconds
    // (e.g. "2026-07-20T14:30:00.123456+00:00" vs "...T14:30:00+00:00").
    // Foundation's .iso8601 strategy rejects the fractional form outright, so
    // we try both formatters ourselves.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Auth

    func login(email: String, password: String) async throws -> User {
        struct LoginBody: Encodable { let email: String; let password: String }
        struct LoginResponse: Decodable { let user: User }
        let body = LoginBody(email: email, password: password)
        let response: LoginResponse = try await send(
            path: "/api/v1/auth/login", method: "POST", body: body
        )
        return response.user
    }

    func logout() async throws {
        try await sendNoContent(path: "/api/v1/auth/logout", method: "POST")
    }

    func me() async throws -> User {
        try await send(path: "/api/v1/me", method: "GET")
    }

    // MARK: - Cases

    func cases(query: CaseQuery = CaseQuery()) async throws -> [CaseSummary] {
        struct CasesResponse: Decodable { let cases: [CaseSummary]; let total: Int }
        var items: [URLQueryItem] = []
        if let q = query.q { items.append(URLQueryItem(name: "q", value: q)) }
        if let difficulty = query.difficulty { items.append(URLQueryItem(name: "difficulty", value: difficulty)) }
        if let industry = query.industry { items.append(URLQueryItem(name: "industry", value: industry)) }
        if let caseType = query.caseType { items.append(URLQueryItem(name: "case_type", value: caseType)) }
        if let school = query.school { items.append(URLQueryItem(name: "school", value: school)) }
        if let limit = query.limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        let response: CasesResponse = try await send(
            path: "/api/v1/cases", method: "GET", queryItems: items
        )
        return response.cases
    }

    func caseDetail(id: Int) async throws -> CaseDetail {
        try await send(path: "/api/v1/cases/\(id)", method: "GET")
    }

    // F4 Library screen (Task 1): same /api/v1/cases endpoint as cases(query:)
    // above, but decodes the full page shape (open_count/done_count) that
    // drives the retired-done divider + count line. cases(query:) is left
    // untouched — CasesViewModel/CaseDetailView still use it until Task 4
    // migrates them onto LibraryService, per the plan's compile-order note.
    func library(query: CaseQuery = CaseQuery()) async throws -> LibraryPage {
        var items: [URLQueryItem] = []
        if let q = query.q { items.append(URLQueryItem(name: "q", value: q)) }
        if let difficulty = query.difficulty { items.append(URLQueryItem(name: "difficulty", value: difficulty)) }
        if let industry = query.industry { items.append(URLQueryItem(name: "industry", value: industry)) }
        if let caseType = query.caseType { items.append(URLQueryItem(name: "case_type", value: caseType)) }
        if let school = query.school { items.append(URLQueryItem(name: "school", value: school)) }
        if let limit = query.limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await send(path: "/api/v1/cases", method: "GET", queryItems: items)
    }

    // Preview/PDF URLs from the API may be relative same-origin paths;
    // resolve them against baseURL so AsyncImage/ShareLink get absolute URLs.
    nonisolated func resolveURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - Proposals

    func proposals() async throws -> [Proposal] {
        struct ProposalsResponse: Decodable { let proposals: [Proposal] }
        let response: ProposalsResponse = try await send(path: "/api/v1/proposals", method: "GET")
        return response.proposals
    }

    func acceptProposal(id: Int, scheduledAt: Date) async throws -> AcceptedSession {
        struct AcceptBody: Encodable { let scheduledAt: Date }
        let body = AcceptBody(scheduledAt: scheduledAt)
        return try await send(
            path: "/api/proposals/\(id)/accept", method: "POST", body: body, allowRecapGate: true
        )
    }

    func declineProposal(id: Int) async throws {
        try await sendNoContent(path: "/api/proposals/\(id)/decline", method: "POST")
    }

    // Recipient-only counter (F3, contract sheet POST /api/proposals/{id}/counter).
    // Response body ({countered, proposal_id, counter_times}) isn't needed by
    // the caller — a 2xx is success, matching createProposal's discard-body style.
    func counterProposal(id: Int, times: [Date]) async throws {
        struct CounterBody: Encodable { let times: [Date] }
        try await sendNoContent(path: "/api/proposals/\(id)/counter", method: "POST", body: CounterBody(times: times))
    }

    // POST /api/proposals/claim/{token} (F3) — empty body; may 409 with the
    // recap gate for a gated candidate.
    func claimProposal(token: String) async throws -> ClaimResult {
        try await send(path: "/api/proposals/claim/\(token)", method: "POST", allowRecapGate: true)
    }

    // GET /api/v1/recaps (F3) — oldest-first, unread-only recap gate feed.
    func recaps() async throws -> [RecapItem] {
        struct RecapsResponse: Decodable { let recaps: [RecapItem] }
        let response: RecapsResponse = try await send(path: "/api/v1/recaps", method: "GET")
        return response.recaps
    }

    // Creates a proposal from the free-now propose flow (Task 9). Hits the
    // non-versioned /api/proposals (native-compatible; no Origin header passes
    // CSRF) with a single "now" proposed time. `proposedTimes` encodes as plain
    // ISO8601 via the shared encoder; nil `message` is omitted.
    //
    // Returns Void: the endpoint responds 200 with the bare proposals-table row
    // (proposed_times_json, no from_name/case_title), which does NOT match the
    // enriched Proposal model — decoding it always threw. We require a 2xx via
    // the raw path and discard the body; the propose flow only needs success.
    func createProposal(toUserId: Int, caseId: Int, fromRole: String, message: String?) async throws {
        struct ProposalBody: Encodable {
            let toUserId: Int
            let caseId: Int
            let fromRole: String
            let message: String?
            let proposedTimes: [Date]
        }
        let body = ProposalBody(
            toUserId: toUserId, caseId: caseId, fromRole: fromRole,
            message: message, proposedTimes: [Date()]
        )
        var request = try makeRequest(path: "/api/proposals", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        _ = try await performRaw(request)
    }

    // MARK: - Availability (AvailabilityService)

    func availability() async throws -> AvailabilityStatus {
        try await send(path: "/api/v1/availability", method: "GET")
    }

    func setFree(minutes: Int) async throws -> AvailabilityStatus {
        struct FreeBody: Encodable { let minutes: Int }
        // The PUT response is {free_until, others} — the same shape as GET, so it
        // decodes straight into AvailabilityStatus (own free_until included).
        return try await send(path: "/api/v1/availability", method: "PUT", body: FreeBody(minutes: minutes))
    }

    func clearFree() async throws {
        try await sendNoContent(path: "/api/v1/availability", method: "DELETE")
    }

    // MARK: - Sessions & dashboard

    func sessions(scope: String) async throws -> [SessionSummary] {
        struct SessionsResponse: Decodable { let sessions: [SessionSummary] }
        let response: SessionsResponse = try await send(
            path: "/api/v1/sessions", method: "GET",
            queryItems: [URLQueryItem(name: "scope", value: scope)]
        )
        return response.sessions
    }

    func dashboard() async throws -> DashboardStats {
        try await send(path: "/api/v1/dashboard", method: "GET")
    }

    // MARK: - Timeline (TimelineService, B7)

    func timeline() async throws -> TimelineDetail {
        try await send(path: "/api/v1/timeline", method: "GET")
    }

    func timelineFirms() async throws -> [FirmCatalogEntry] {
        struct FirmsResponse: Decodable { let firms: [FirmCatalogEntry] }
        let response: FirmsResponse = try await send(path: "/api/v1/timeline/firms", method: "GET")
        return response.firms
    }

    func trackFirm(firmId: Int) async throws {
        struct TrackBody: Encodable { let firmId: Int }
        try await sendNoContent(path: "/api/v1/timeline/firms", method: "POST", body: TrackBody(firmId: firmId))
    }

    func untrackFirm(firmId: Int) async throws {
        try await sendNoContent(path: "/api/v1/timeline/firms/\(firmId)", method: "DELETE")
    }

    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult {
        struct ResultBody: Encodable { let outcome: String }
        return try await send(
            path: "/api/v1/timeline/firms/\(firmId)/result", method: "POST",
            body: ResultBody(outcome: outcome)
        )
    }

    // MARK: - Recommendations (RecommendationService, B4)

    func recommendations(exclude: [Int]) async throws -> [Recommendation] {
        struct RecommendationsResponse: Decodable { let recommendations: [Recommendation] }
        var items: [URLQueryItem] = []
        if !exclude.isEmpty {
            items.append(URLQueryItem(name: "exclude", value: exclude.map(String.init).joined(separator: ",")))
        }
        let response: RecommendationsResponse = try await send(
            path: "/api/v1/recommendations", method: "GET", queryItems: items
        )
        return response.recommendations
    }

    // MARK: - Gauntlet & boards (GauntletService/BoardService, B8)

    func gauntlet() async throws -> Gauntlet {
        try await send(path: "/api/v1/drills/gauntlet", method: "GET")
    }

    func groupBoard() async throws -> GroupBoard {
        try await send(
            path: "/api/v1/drills/boards", method: "GET",
            queryItems: [URLQueryItem(name: "scope", value: "group")]
        )
    }

    // MARK: - Community (CommunityService, F8)

    func connections() async throws -> [Connection] {
        struct ConnectionsResponse: Decodable { let connections: [Connection] }
        let response: ConnectionsResponse = try await send(path: "/api/v1/connections", method: "GET")
        return response.connections
    }

    func groups() async throws -> [GroupSummary] {
        struct GroupsResponse: Decodable { let groups: [GroupSummary] }
        let response: GroupsResponse = try await send(path: "/api/v1/groups", method: "GET")
        return response.groups
    }

    func createGroup(name: String) async throws -> GroupSummary {
        struct CreateGroupBody: Encodable { let name: String }
        return try await send(path: "/api/v1/groups", method: "POST", body: CreateGroupBody(name: name))
    }

    func group(id: Int) async throws -> GroupDetail {
        try await send(path: "/api/v1/groups/\(id)", method: "GET")
    }

    func transferGroupAdmin(id: Int, userId: Int) async throws {
        struct TransferBody: Encodable { let userId: Int }
        try await sendNoContent(path: "/api/v1/groups/\(id)/transfer", method: "POST", body: TransferBody(userId: userId))
    }

    func groupProgress(id: Int) async throws -> [GroupProgressMember] {
        struct ProgressResponse: Decodable { let members: [GroupProgressMember] }
        let response: ProgressResponse = try await send(path: "/api/v1/groups/\(id)/progress", method: "GET")
        return response.members
    }

    func schoolStanding() async throws -> SchoolStanding {
        try await send(path: "/api/v1/leaderboards/school", method: "GET")
    }

    // MARK: - Drills boards (F7)

    func schoolBoard() async throws -> SchoolBoard {
        try await send(
            path: "/api/v1/drills/boards", method: "GET",
            queryItems: [URLQueryItem(name: "scope", value: "school")]
        )
    }

    func globalBoard() async throws -> GlobalBoard {
        try await send(
            path: "/api/v1/drills/boards", method: "GET",
            queryItems: [URLQueryItem(name: "scope", value: "global")]
        )
    }

    func schoolsBoard() async throws -> SchoolsBoard {
        try await send(
            path: "/api/v1/drills/boards", method: "GET",
            queryItems: [URLQueryItem(name: "scope", value: "schools")]
        )
    }

    // POST .../gauntlet/attempts — server re-scores against the regenerated
    // set (client `value`/`choiceIndex` never trusted for grading). One
    // submission/user/day: a repeat -> 409, rethrown as the typed
    // GauntletError.alreadySubmitted so the VM can recover via gauntlet().result.
    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult {
        struct SubmitBody: Encodable { let answers: [GauntletAttempt] }
        do {
            return try await send(
                path: "/api/v1/drills/gauntlet/attempts", method: "POST",
                body: SubmitBody(answers: answers)
            )
        } catch APIError.server(409) {
            throw GauntletError.alreadySubmitted
        }
    }

    func trends() async throws -> GauntletTrends {
        try await send(path: "/api/v1/drills/trends", method: "GET")
    }

    // MARK: - Devices

    func registerDevice(token: String) async throws {
        struct DeviceBody: Encodable { let token: String; let platform: String = "ios" }
        try await sendNoContent(path: "/api/v1/devices", method: "POST", body: DeviceBody(token: token))
    }

    // MARK: - Profile & settings (B5)

    func profile() async throws -> ProfileDetail {
        try await send(path: "/api/v1/profile", method: "GET")
    }

    // A nil field omits the key (synthesized Encodable uses encodeIfPresent); B5's
    // ProfileUpdate defaults each to None, so an omitted key clears that field —
    // which is exactly the "user emptied it" intent the avatar-sheet editor sends.
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail {
        struct Body: Encodable { let displayName: String?; let bio: String?; let linkedinUrl: String? }
        return try await send(
            path: "/api/v1/profile", method: "PUT",
            body: Body(displayName: displayName, bio: bio, linkedinUrl: linkedinUrl)
        )
    }

    func uploadProfilePhoto(data: Data, mime: String) async throws -> String {
        struct PhotoResponse: Decodable { let photoUrl: String }
        let boundary = "CaseRoomBoundary-\(UUID().uuidString)"
        var request = try makeRequest(path: "/api/v1/profile/photo", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartPhotoBody(boundary: boundary, mime: mime, data: data)
        let responseData = try await performRaw(request)
        return try decoder.decode(PhotoResponse.self, from: responseData).photoUrl
    }

    func notificationSettings() async throws -> NotificationSettings {
        try await send(path: "/api/v1/settings/notifications", method: "GET")
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings {
        try await send(path: "/api/v1/settings/notifications", method: "PUT", body: settings)
    }

    private static func multipartPhotoBody(boundary: String, mime: String, data: Data) -> Data {
        let ext = mime == "image/png" ? "png" : (mime == "image/webp" ? "webp" : "jpg")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Drills (DrillService)

    func dailyDrill() async throws -> Drill {
        // Server wraps the drill in {drill, date}; the client only needs the drill.
        struct DailyResponse: Decodable { let drill: Drill; let date: String }
        let response: DailyResponse = try await send(path: "/api/v1/drills/daily", method: "GET")
        return response.drill
    }

    func templatePack() async throws -> Data {
        // Raw {version, templates} JSON — the on-device engine's offline cache
        // (Task 6). Returned as Data so callers persist it verbatim.
        let request = try makeRequest(path: "/api/v1/drills/templates", method: "GET")
        return try await performRaw(request)
    }

    func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws {
        struct AttemptBody: Encodable {
            let drillType: String
            let source: String
            let drillKey: String?
            let correct: Bool
        }
        try await sendNoContent(
            path: "/api/v1/drills/attempts", method: "POST",
            body: AttemptBody(drillType: drillType, source: source, drillKey: drillKey, correct: correct)
        )
    }

    // MARK: - Live Activity (Task 10)

    func registerLiveActivity(sessionId: Int, pushToken: String) async throws {
        struct LiveActivityBody: Encodable { let sessionId: Int; let pushToken: String }
        try await sendNoContent(
            path: "/api/v1/live-activity", method: "POST",
            body: LiveActivityBody(sessionId: sessionId, pushToken: pushToken)
        )
    }

    // MARK: - Practice sessions (SessionService)

    func sessionDetail(id: Int) async throws -> SessionDetail {
        try await send(path: "/api/practice/\(id)", method: "GET")
    }

    func joinConfig(id: Int) async throws -> JoinConfig {
        try await send(path: "/api/practice/\(id)/join-config", method: "GET")
    }

    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail {
        struct ConsentBody: Encodable { let consent: Bool }
        return try await send(path: "/api/practice/\(id)/consent", method: "POST", body: ConsentBody(consent: consent))
    }

    func transition(id: Int, target: String) async throws -> SessionDetail {
        struct StateBody: Encodable { let target: String }
        return try await send(path: "/api/practice/\(id)/state", method: "POST", body: StateBody(target: target))
    }

    func rubric(id: Int) async throws -> RubricState {
        try await send(path: "/api/practice/\(id)/rubric", method: "GET")
    }

    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double {
        struct RubricDraftBody: Encodable { let items: [String: RubricItemScore]; let notesMd: String }
        struct SaveResponse: Decodable { let saved: Bool; let gradePreview: Double }
        let body = RubricDraftBody(items: items, notesMd: notesMd)
        let response: SaveResponse = try await send(path: "/api/practice/\(id)/rubric", method: "PUT", body: body)
        return response.gradePreview
    }

    func reveal(id: Int, exhibitId: Int) async throws {
        struct RevealBody: Encodable { let exhibitId: Int }
        try await sendNoContent(path: "/api/practice/\(id)/reveals", method: "POST", body: RevealBody(exhibitId: exhibitId))
    }

    func exhibits(id: Int) async throws -> [ExhibitMeta] {
        struct ExhibitsResponse: Decodable { let exhibits: [ExhibitMeta] }
        let response: ExhibitsResponse = try await send(path: "/api/practice/\(id)/exhibits", method: "GET")
        return response.exhibits
    }

    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data {
        let request = try makeRequest(path: "/api/practice/\(id)/exhibit-blob/\(exhibitId)", method: "GET")
        return try await performRaw(request)
    }

    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws {
        let boundary = "CaseRoomBoundary-\(UUID().uuidString)"
        var request = try makeRequest(path: "/api/practice/\(id)/recordings/chunk", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartRecordingBody(boundary: boundary, seq: seq, mime: mime, blob: blob)
        _ = try await performRaw(request, allowConflictDetail: true)
    }

    func completeRecording(id: Int) async throws {
        try await sendNoContent(path: "/api/practice/\(id)/recordings/complete", method: "POST")
    }

    func finalize(id: Int, grade: Double?) async throws -> Finalized {
        // Synthesized Codable omits nil optionals via encodeIfPresent; the
        // API expects the "grade" key present with an explicit null, so
        // this encodes it directly instead.
        struct FinalizeBody: Encodable {
            let grade: Double?
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(grade, forKey: .grade)
            }
            enum CodingKeys: String, CodingKey { case grade }
        }
        return try await send(path: "/api/practice/\(id)/finalize", method: "POST", body: FinalizeBody(grade: grade))
    }

    // MARK: - Pairing (PairService)

    func pairCreate(caseId: Int) async throws -> PairToken {
        struct PairCreateBody: Encodable { let caseId: Int }
        return try await send(
            path: "/api/practice/pair/create", method: "POST", body: PairCreateBody(caseId: caseId)
        )
    }

    func pairStatus(token: String) async throws -> Int? {
        struct StatusResponse: Decodable { let sessionId: Int? }
        let response: StatusResponse = try await send(
            path: "/api/practice/pair/status/\(token)", method: "GET"
        )
        return response.sessionId
    }

    func pairClaim(token: String) async throws -> Int {
        struct PairClaimBody: Encodable { let token: String }
        struct ClaimResponse: Decodable { let sessionId: Int }
        let response: ClaimResponse = try await send(
            path: "/api/practice/pair/claim", method: "POST", body: PairClaimBody(token: token),
            allowRecapGate: true
        )
        return response.sessionId
    }

    // MARK: - Get-cased-now (GetCasedService, F3-T3)

    // Case-less-capable pairing for the "Get cased now" sheet: nil mints a
    // general pairing code (candidate hasn't chosen a case yet); a concrete id
    // scopes it to a case (T4). The existing PairService.pairCreate takes a
    // non-optional Int (interviewer-flow, always case-scoped), so this is a
    // sibling overload rather than a change to that contract. Forces `case_id`
    // to explicit null when nil so the server distinguishes case-less from a
    // malformed/absent field.
    func pairCreate(caseId: Int?) async throws -> PairToken {
        struct FlexPairBody: Encodable {
            let caseId: Int?
            enum CodingKeys: String, CodingKey { case caseId }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(caseId, forKey: .caseId)   // null when nil
            }
        }
        return try await send(
            path: "/api/practice/pair/create", method: "POST", body: FlexPairBody(caseId: caseId)
        )
    }

    // A "ping" from the Get-cased-now board — a now-invite to a free classmate.
    // POST /api/proposals with case_id:null, from_role:"candidate", one "now"
    // proposed time. Mirrors createProposal's discard-body style (the endpoint
    // returns the bare proposals row, which doesn't decode into Proposal).
    func createNowInvite(toUserId: Int) async throws {
        struct NowInviteBody: Encodable {
            let toUserId: Int
            let caseId: Int?
            let fromRole: String
            let proposedTimes: [Date]
            enum CodingKeys: String, CodingKey { case toUserId, caseId, fromRole, proposedTimes }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(toUserId, forKey: .toUserId)
                try container.encode(caseId, forKey: .caseId)   // explicit null
                try container.encode(fromRole, forKey: .fromRole)
                try container.encode(proposedTimes, forKey: .proposedTimes)
            }
        }
        let body = NowInviteBody(
            toUserId: toUserId, caseId: nil, fromRole: "candidate", proposedTimes: [Date()]
        )
        var request = try makeRequest(path: "/api/proposals", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        _ = try await performRaw(request)
    }

    private static func multipartRecordingBody(boundary: String, seq: Int, mime: String, blob: Data) -> Data {
        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField(name: "seq", value: String(seq))
        appendField(name: "mime", value: mime)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"blob\"; filename=\"chunk.bin\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(blob)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Core request plumbing

    private func makeRequest(
        path: String, method: String, queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError.transport(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func send<Response: Decodable>(
        path: String, method: String, queryItems: [URLQueryItem] = [], allowRecapGate: Bool = false
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
        return try await perform(request, allowRecapGate: allowRecapGate)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String, method: String, body: Body, queryItems: [URLQueryItem] = [], allowRecapGate: Bool = false
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request, allowRecapGate: allowRecapGate)
    }

    private func sendNoContent(
        path: String, method: String, queryItems: [URLQueryItem] = []
    ) async throws {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
        _ = try await performRaw(request)
    }

    private func sendNoContent<Body: Encodable>(
        path: String, method: String, body: Body, queryItems: [URLQueryItem] = []
    ) async throws {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        _ = try await performRaw(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest, allowRecapGate: Bool = false) async throws -> Response {
        let data = try await performRaw(request, allowRecapGate: allowRecapGate)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func performRaw(
        _ request: URLRequest, allowConflictDetail: Bool = false, allowRecapGate: Bool = false
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        if allowConflictDetail, httpResponse.statusCode == 409,
           let expected = Self.expectedSeq(from: data) {
            throw RecordingChunkError.seqMismatch(expected: expected)
        }
        if allowRecapGate, let sessionId = Self.decodeRecapGate(status: httpResponse.statusCode, data: data) {
            throw CaseGateError.blockedByRecap(sessionId)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.server(httpResponse.statusCode)
        }
        return data
    }

    // Parses {"detail": "expected seq N"} from a 409 chunk-upload response.
    private static func expectedSeq(from data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? String,
              let match = detail.range(of: #"expected seq (\d+)"#, options: .regularExpression) else {
            return nil
        }
        let numberString = detail[match].split(separator: " ").last.map(String.init) ?? ""
        return Int(numberString)
    }

    // Parses {"detail": {"blocked_by_recap": session_id}} from a 409 recap-gate
    // response (B3 contract sheet). Only relevant on 409 — other statuses
    // return nil so performRaw falls through to its normal APIError.server path.
    private static func decodeRecapGate(status: Int, data: Data) -> Int? {
        guard status == 409,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? [String: Any],
              let sessionId = detail["blocked_by_recap"] as? Int else {
            return nil
        }
        return sessionId
    }
}
