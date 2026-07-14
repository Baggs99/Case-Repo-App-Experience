/*
 * Purpose: Talks to the CaseRoom /api/v1 backend over cookie-session auth.
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

actor APIClient {
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

    func acceptProposal(id: Int) async throws -> AcceptedSession {
        try await send(path: "/api/proposals/\(id)/accept", method: "POST")
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
