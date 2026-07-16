/*
 * Purpose: The "I'm free now" App Intent — toggles the user's free-now
 *          broadcast from Siri, Shortcuts, the Action button, and the widget
 *          button. It is Shared so it compiles into the widget extension and
 *          runs in that process when tapped on the widget; it talks to the API
 *          via AvailabilityLite (group cookies) with no app-only imports.
 * Inputs: current availability from /api/v1/availability (group cookie auth);
 *         API_BASE_URL from the *hosting bundle's* Info.plist (localhost fallback).
 * Outputs: PUT/DELETE /api/v1/availability, a widget-snapshot.json RMW write,
 *          and a CaseRoomFreeNow timeline reload.
 * Run: invoked by the system; nextAction(current:) is the unit-tested core.
 */

import AppIntents
import Foundation
import WidgetKit

struct ToggleFreeNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Free Now"
    static let description = IntentDescription("Broadcast that you're free to practice now, or turn it off.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = AvailabilityLite()
        do {
            let current = try await client.status()
            switch Self.nextAction(current: current) {
            case .goFree:
                let updated = try await client.setFree(minutes: 60)
                Self.updateSnapshot(freeUntil: updated.freeUntil)
                let count = updated.others.count
                return .result(dialog: IntentDialog(
                    stringLiteral: "You're free for the next hour — \(count) classmates are free now."
                ))
            case .goOffline:
                try await client.clear()
                Self.updateSnapshot(freeUntil: nil)
                return .result(dialog: "You're no longer free.")
            }
        } catch {
            // Never throw out of perform() — a dead network shouldn't surface a
            // raw error to Siri/the widget.
            return .result(dialog: "Couldn't update — open CaseRoom and try again.")
        }
    }

    enum ToggleAction: Equatable { case goFree, goOffline }

    /// Pure toggle decision: currently free (a live broadcast) -> go offline;
    /// otherwise go free. The server only returns `freeUntil` while a broadcast
    /// is active, so a non-nil value means "currently free".
    static func nextAction(current: AvailabilityStatus) -> ToggleAction {
        current.freeUntil != nil ? .goOffline : .goFree
    }

    // Read-modify-write: the dashboard flow owns streak/drill/session fields, so
    // carry them forward and only change freeUntil, then reload just the
    // free-now widget timeline (matches FreeNowViewModel's convention).
    private static func updateSnapshot(freeUntil: Date?) {
        let existing = SnapshotStore.read()
        let snapshot = WidgetSnapshot(
            streakDays: existing?.streakDays ?? 0,
            drillDoneToday: existing?.drillDoneToday ?? false,
            nextSessionTitle: existing?.nextSessionTitle,
            nextSessionOther: existing?.nextSessionOther,
            nextSessionAt: existing?.nextSessionAt,
            freeUntil: freeUntil,
            updatedAt: Date()
        )
        SnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "CaseRoomFreeNow")
    }
}

/// A minimal availability client for the widget/Shared context — it must not
/// import APIClient (app-target only), so it reconstructs just what it needs:
/// the base URL from the hosting bundle's Info.plist, a group-cookie session
/// (authenticated in both the app and the widget processes), and the app's
/// two-formatter ISO8601 date decoding.
struct AvailabilityLite {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: configured) {
            baseURL = url
        } else {
            baseURL = URL(string: "http://127.0.0.1:8077")!
        }
        session = URLSession(configuration: AppGroup.makeURLSessionConfiguration())

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.fractionalFormatter.date(from: string) { return date }
            if let date = Self.plainFormatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected ISO8601 date string, got \(string)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func status() async throws -> AvailabilityStatus {
        try await perform(request("/api/v1/availability", method: "GET"))
    }

    func setFree(minutes: Int) async throws -> AvailabilityStatus {
        struct Body: Encodable { let minutes: Int }
        var request = request("/api/v1/availability", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Body(minutes: minutes))
        return try await perform(request)
    }

    func clear() async throws {
        _ = try await performRaw(request("/api/v1/availability", method: "DELETE"))
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try decoder.decode(Response.self, from: try await performRaw(request))
    }

    @discardableResult
    private func performRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AvailabilityLiteError.badResponse
        }
        return data
    }

    enum AvailabilityLiteError: Error { case badResponse }

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
}
