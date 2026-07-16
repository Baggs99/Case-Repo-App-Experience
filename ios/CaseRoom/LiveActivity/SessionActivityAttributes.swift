/*
 * Purpose: ActivityKit attributes + content-state for a practice session's
 *          Live Activity (lock-screen banner + Dynamic Island). Shared
 *          source, compiled into both the CaseRoom app target and the
 *          CaseRoomWidgets extension target.
 * Inputs: none (pure data types).
 * Outputs: none. CRITICAL: ContentState's CodingKeys must exactly match the
 *          backend push payload keys (webapp/push/live_activity.py::
 *          _content_state) — ActivityKit decodes pushed content-state with a
 *          PLAIN decoder, no snake_case conversion.
 * Run: consumed by LiveActivityController (start/end) and SessionLiveActivity
 *      (widget rendering).
 */

import ActivityKit

struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let state: String
        let role: String
        let counterpartName: String
        let scheduledAt: String?
        let startedAt: String?

        enum CodingKeys: String, CodingKey {
            case state, role
            case counterpartName = "counterpart_name"
            case scheduledAt = "scheduled_at"
            case startedAt = "started_at"
        }
    }

    let sessionId: Int
}
