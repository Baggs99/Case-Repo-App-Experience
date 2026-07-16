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
import WidgetKit

protocol TodayService {
    func dashboard() async throws -> DashboardStats
}

extension APIClient: TodayService {}

@Observable
final class TodayViewModel {
    var nextSession: SessionSummary?
    var streakWeeks = 0
    var streakDays = 0
    var drillDoneToday = false
    var sessionsFinalized = 0
    var errorMessage: String?

    private let service: TodayService
    private let writeSnapshot: (WidgetSnapshot) -> Void
    private let reloadWidgets: () -> Void

    init(service: TodayService = APIClient.shared,
         writeSnapshot: @escaping (WidgetSnapshot) -> Void = { SnapshotStore.write($0) },
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.service = service
        self.writeSnapshot = writeSnapshot
        self.reloadWidgets = reloadWidgets
    }

    func load() async {
        errorMessage = nil
        do {
            let stats = try await service.dashboard()
            nextSession = stats.nextSession
            streakWeeks = stats.streakWeeks
            streakDays = stats.streakDays ?? 0
            drillDoneToday = stats.drillDoneToday ?? false
            sessionsFinalized = stats.sessionsFinalized
            writeWidgetSnapshot(from: stats)
        } catch {
            errorMessage = "Couldn't load your dashboard. Try again."
        }
    }

    // Mirrors the freshly loaded dashboard into the widget's shared snapshot so
    // the home-screen widget reflects streak/drill/next-session state without
    // its own network call.
    private func writeWidgetSnapshot(from stats: DashboardStats) {
        let snapshot = WidgetSnapshot(
            streakDays: stats.streakDays ?? 0,
            drillDoneToday: stats.drillDoneToday ?? false,
            nextSessionTitle: stats.nextSession?.caseTitle,
            nextSessionOther: stats.nextSession?.otherUser,
            nextSessionAt: stats.nextSession?.scheduledAt,
            freeUntil: nil,
            updatedAt: Date()
        )
        writeSnapshot(snapshot)
        reloadWidgets()
    }
}
