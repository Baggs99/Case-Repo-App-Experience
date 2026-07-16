/*
 * Purpose: Fire-and-forget recording of drill attempts — posts to the backend,
 *          and on any failure queues the attempt in the App Group's UserDefaults
 *          so flushPending() (called at app foreground) can retry it later.
 * Inputs: a DrillService; a UserDefaults (the App Group suite, or .standard when
 *         the group is unavailable — mirrors AppGroup's fallback philosophy).
 * Outputs: attempt POSTs; the "pendingDrillAttempts" queue in UserDefaults.
 * Run: await AttemptRecorder(service: APIClient.shared).record(drill:source:correct:)
 */

import Foundation

// One queued-for-retry attempt. Encoded as a JSON array under the
// "pendingDrillAttempts" key so the optional drillKey survives (UserDefaults
// dictionaries cannot hold nil).
struct PendingAttempt: Codable, Equatable {
    let drillType: String
    let source: String
    let drillKey: String?
    let correct: Bool
}

struct AttemptRecorder {
    static let queueKey = "pendingDrillAttempts"

    let service: DrillService
    let defaults: UserDefaults

    init(service: DrillService, defaults: UserDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard) {
        self.service = service
        self.defaults = defaults
    }

    // Posts the attempt; on any failure queues it and returns. Never throws to
    // the UI — a dropped attempt is a background retry, not a user-facing error.
    func record(drill: Drill, source: String, correct: Bool) async {
        let attempt = PendingAttempt(
            drillType: drill.drillType.rawValue, source: source, drillKey: drill.key, correct: correct
        )
        do {
            try await service.recordAttempt(
                drillType: attempt.drillType, source: attempt.source,
                drillKey: attempt.drillKey, correct: attempt.correct
            )
        } catch {
            enqueue(attempt)
        }
    }

    // Retries every queued attempt; drops the ones that post, keeps the ones
    // that fail again (order preserved). A no-op when the queue is empty.
    func flushPending() async {
        let pending = loadQueue()
        guard !pending.isEmpty else { return }
        var stillPending: [PendingAttempt] = []
        for attempt in pending {
            do {
                try await service.recordAttempt(
                    drillType: attempt.drillType, source: attempt.source,
                    drillKey: attempt.drillKey, correct: attempt.correct
                )
            } catch {
                stillPending.append(attempt)
            }
        }
        saveQueue(stillPending)
    }

    // MARK: - Queue persistence

    private func enqueue(_ attempt: PendingAttempt) {
        var queue = loadQueue()
        queue.append(attempt)
        saveQueue(queue)
    }

    private func loadQueue() -> [PendingAttempt] {
        guard let data = defaults.data(forKey: Self.queueKey),
              let queue = try? JSONDecoder().decode([PendingAttempt].self, from: data) else {
            return []
        }
        return queue
    }

    private func saveQueue(_ queue: [PendingAttempt]) {
        if queue.isEmpty {
            defaults.removeObject(forKey: Self.queueKey)
            return
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: Self.queueKey)
    }
}
