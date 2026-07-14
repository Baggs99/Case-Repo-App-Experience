/*
 * Purpose: Drives the Today tab — the soonest upcoming session, streak, and
 *          finalized-session count, all sourced from a single dashboard()
 *          call, via an injectable TodayService so tests never touch the
 *          network.
 * Inputs: TodayService (default APIClient.shared).
 * Outputs: none.
 * Run: instantiated by TodayView; call load() from .task.
 */

import Foundation
import Observation

protocol TodayService {
    func dashboard() async throws -> DashboardStats
}

extension APIClient: TodayService {}

@Observable
final class TodayViewModel {
    var nextSession: SessionSummary?
    var streakWeeks = 0
    var sessionsFinalized = 0
    var errorMessage: String?

    private let service: TodayService

    init(service: TodayService = APIClient.shared) {
        self.service = service
    }

    func load() async {
        errorMessage = nil
        do {
            let stats = try await service.dashboard()
            nextSession = stats.nextSession
            streakWeeks = stats.streakWeeks
            sessionsFinalized = stats.sessionsFinalized
        } catch {
            errorMessage = "Couldn't load your dashboard. Try again."
        }
    }
}
