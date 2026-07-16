/*
 * Purpose: The drill service abstraction and the server-backed DrillEngine —
 *          DrillService (implemented by APIClient), DrillEngine (Task 6 adds an
 *          on-device engine), and ServerDrillEngine that fetches the daily drill.
 * Inputs: a DrillService (the live APIClient in the app).
 * Outputs: none (network side effects flow through the service).
 * Run: try await ServerDrillEngine(service: APIClient.shared).dailyDrill()
 */

import Foundation

// The three drill endpoints the client needs. APIClient conforms; Task 6's
// on-device engine reuses recordAttempt/templatePack. dailyDrill() already
// unwraps the {drill, date} envelope to the domain Drill.
protocol DrillService {
    func dailyDrill() async throws -> Drill
    func templatePack() async throws -> Data
    func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws
}

// Source of the daily drill. `sourceLabel` ("server" | "on_device") is written
// into the attempt POST so the backend knows which engine graded it.
protocol DrillEngine {
    func dailyDrill() async throws -> Drill
    var sourceLabel: String { get }
}

struct ServerDrillEngine: DrillEngine {
    let service: DrillService

    var sourceLabel: String { "server" }

    func dailyDrill() async throws -> Drill {
        try await service.dailyDrill()
    }
}
