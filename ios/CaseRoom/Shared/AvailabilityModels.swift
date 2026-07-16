/*
 * Purpose: Free-now availability Codables shared by the app and the widget
 *          extension — the widget's ToggleFreeNowIntent (running in the
 *          extension process) decodes these, so they live in Shared, not the
 *          app-only Models.swift.
 * Inputs: JSON from GET/PUT /api/v1/availability, decoded snake_case.
 * Outputs: none (pure data types).
 * Run: consumed by APIClient (app) and AvailabilityLite (widget/Shared).
 */

import Foundation

// GET/PUT /api/v1/availability both return this shape; `freeUntil` is the
// caller's own broadcast (null when not free) and `others` are classmates
// currently free. The server coalesces `name` to the user's email, so it is
// never null.
struct AvailabilityStatus: Codable, Equatable {
    let freeUntil: Date?
    let others: [FreeUser]
}

struct FreeUser: Codable, Identifiable, Equatable {
    let userId: Int
    let name: String
    let freeUntil: Date
    var id: Int { userId }
}
