/*
 * Purpose: Talks to the CaseRoom /api/v1 and /api/practice endpoints over
 *          cookie-session auth.
 * Inputs: Info.plist key API_BASE_URL (falls back to localhost:8077 for sim).
 * Outputs: none (network side effects only); cookies persist via
 *          HTTPCookieStorage.shared, the URLSession default.
 * Run: APIClient.shared.login(email:password:) etc., from SessionStore.
 */

import Foundation

enum APIError: Error {
    case unauthorized
    case server(Int)
    case decoding(Error)
    case transport(Error)
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
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail
    func transition(id: Int, target: String) async throws -> SessionDetail
    func rubric(id: Int) async throws -> RubricState
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double
    func reveal(id: Int, exhibitId: Int) async throws
    func exhibits(id: Int) async throws -> [ExhibitMeta]
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws
    func completeRecording(id: Int) async throws
    func finalize(id: Int, grade: Double?) async throws
}

actor APIClient: SessionService {
    static let shared = APIClient()

    // Immutable and Sendable, so safe to read from outside actor isolation
    // (e.g. resolving relative preview/PDF URLs from a SwiftUI view).
    nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
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
        return try await send(path: "/api/proposals/\(id)/accept", method: "POST", body: body)
    }

    func declineProposal(id: Int) async throws {
        try await sendNoContent(path: "/api/proposals/\(id)/decline", method: "POST")
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

    // MARK: - Devices

    func registerDevice(token: String) async throws {
        struct DeviceBody: Encodable { let token: String; let platform: String = "ios" }
        try await sendNoContent(path: "/api/v1/devices", method: "POST", body: DeviceBody(token: token))
    }

    // MARK: - Practice sessions (SessionService)

    func sessionDetail(id: Int) async throws -> SessionDetail {
        try await send(path: "/api/practice/\(id)", method: "GET")
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
        _ = try await performRaw(request)
    }

    func completeRecording(id: Int) async throws {
        try await sendNoContent(path: "/api/practice/\(id)/recordings/complete", method: "POST")
    }

    func finalize(id: Int, grade: Double?) async throws {
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
        try await sendNoContent(path: "/api/practice/\(id)/finalize", method: "POST", body: FinalizeBody(grade: grade))
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
        path: String, method: String, queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
        return try await perform(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String, method: String, body: Body, queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
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

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performRaw(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func performRaw(_ request: URLRequest) async throws -> Data {
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
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.server(httpResponse.statusCode)
        }
        return data
    }
}
