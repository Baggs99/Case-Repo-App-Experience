/*
 * Purpose: The widget's home-screen snapshot model and its file store — a
 *          small JSON document in the App Group container that the app writes
 *          (drill/free-now/next-session state) and the widget process reads.
 * Inputs: WidgetSnapshot values from the app; widget-snapshot.json in the
 *         App Group container.
 * Outputs: reads/writes/removes widget-snapshot.json in the group container.
 * Run: SnapshotStore.write(snapshot) from the app; SnapshotStore.read() from
 *      the widget timeline provider; SnapshotStore.clear() on logout.
 */

import Foundation

struct WidgetSnapshot: Codable, Equatable {
    var streakDays: Int
    var drillDoneToday: Bool
    var nextSessionTitle: String?
    var nextSessionOther: String?
    var nextSessionAt: Date?
    var freeUntil: Date?
    var updatedAt: Date
}

struct SnapshotStore {
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // Plain ISO8601 (no fractional seconds) so the widget process decodes the
    // same string form with an identically configured formatter.
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = iso8601.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Expected plain ISO8601 date, got \(string)"
                )
            }
            return date
        }
        return decoder
    }()
}
