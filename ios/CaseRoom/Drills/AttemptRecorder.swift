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

// An actor, not a struct: record() and flushPending() run non-atomic
// load-modify-save on UserDefaults, and a struct offers no isolation across the
// network `await`. Concurrent record() + flushPending() on a struct could lose
// an attempt (flush's final save clobbering an append that landed mid-flight).
// The actor serializes every queue mutation and — critically — the network POST
// happens OUTSIDE any load-save pair, so no `await` ever sits between a queue
// read and its matching write.
actor AttemptRecorder {
    static let queueKey = "pendingDrillAttempts"
    // Cap the retry backlog so an extended offline streak can't grow the App
    // Group defaults without bound. Oldest attempts are dropped first.
    static let maxQueue = 50

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
            // Synchronous, actor-isolated: load+append+cap+save runs atomically.
            enqueue(attempt)
        }
    }

    // Retries every queued attempt; drops the ones that post, re-queues the ones
    // that fail again. A no-op when the queue is empty.
    //
    // Ordering matters for actor-safety: we lift the whole queue out and clear
    // it under isolation (loadQueue + saveQueue([]), no await between), THEN
    // release isolation for the network POSTs. Attempts that fail again are
    // re-appended via enqueue() — a second serialized mutation that loads the
    // *current* queue, so any record() that enqueued while we were awaiting is
    // preserved rather than clobbered.
    func flushPending() async {
        let pending = loadQueue()
        guard !pending.isEmpty else { return }
        saveQueue([])
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
        for attempt in stillPending {
            enqueue(attempt)
        }
    }

    // MARK: - Queue persistence

    private func enqueue(_ attempt: PendingAttempt) {
        var queue = loadQueue()
        queue.append(attempt)
        if queue.count > Self.maxQueue {
            queue.removeFirst(queue.count - Self.maxQueue)
        }
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
