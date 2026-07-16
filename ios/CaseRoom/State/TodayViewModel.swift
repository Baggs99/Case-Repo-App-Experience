/*
 * Purpose: Drives the Today tab — the soonest upcoming session, streak, drill
 *          state, and finalized-session count from a single dashboard() call,
 *          plus an optimistic drill-completion mirror on sheet dismissal.
 * Inputs: TodayService (default APIClient.shared); injectable snapshot
 *         read/write + widget-reload hooks (default SnapshotStore/WidgetCenter).
 * Outputs: a widget-snapshot.json write after each successful load.
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
    /// The background reconcile-with-server task kicked by a completed drill
    /// sheet's dismissal, exposed so tests can await it deterministically.
    private(set) var reloadTask: Task<Void, Never>?

    private let service: TodayService
    private let readSnapshot: () -> WidgetSnapshot?
    private let writeSnapshot: (WidgetSnapshot) -> Void
    private let reloadWidgets: () -> Void

    init(service: TodayService = APIClient.shared,
         readSnapshot: @escaping () -> WidgetSnapshot? = { SnapshotStore.read() },
         writeSnapshot: @escaping (WidgetSnapshot) -> Void = { SnapshotStore.write($0) },
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.service = service
        self.readSnapshot = readSnapshot
        self.writeSnapshot = writeSnapshot
        self.reloadWidgets = reloadWidgets
    }

    func load(silent: Bool = false) async {
        if !silent { errorMessage = nil }
        do {
            let stats = try await service.dashboard()
            nextSession = stats.nextSession
            streakWeeks = stats.streakWeeks
            streakDays = stats.streakDays ?? 0
            drillDoneToday = stats.drillDoneToday ?? false
            sessionsFinalized = stats.sessionsFinalized
            errorMessage = nil
            writeWidgetSnapshot(from: stats)
        } catch {
            // A silent (non-interactive) reconcile must not replace the tab's
            // content with the error view — offline on-device drills hit this.
            if !silent { errorMessage = "Couldn't load your dashboard. Try again." }
        }
    }

    // Optimistic mirror of the drill sheet's outcome so the card flips without
    // a manual refresh: same guarded streak bump DrillViewModel applied to the
    // snapshot (only on the first completion of the day), then a background
    // reload so server truth reconciles when online. A failed reload (offline
    // FM path) leaves the optimistic values in place — load() only touches
    // fields on success. A dismissal without an answered drill is a no-op.
    func drillSheetDismissed(completed: Bool) {
        guard completed else { return }
        if !drillDoneToday {
            streakDays += 1
        }
        drillDoneToday = true
        reloadTask = Task { await self.load(silent: true) }
    }

    // Mirrors the freshly loaded dashboard into the widget's shared snapshot so
    // the home-screen widget reflects streak/drill/next-session state without
    // its own network call. freeUntil is owned by another writer (the free-now
    // flow) — carry the current value forward rather than clobbering it.
    private func writeWidgetSnapshot(from stats: DashboardStats) {
        let snapshot = WidgetSnapshot(
            streakDays: stats.streakDays ?? 0,
            drillDoneToday: stats.drillDoneToday ?? false,
            nextSessionTitle: stats.nextSession?.caseTitle,
            nextSessionOther: stats.nextSession?.otherUser,
            nextSessionAt: stats.nextSession?.scheduledAt,
            freeUntil: readSnapshot()?.freeUntil,
            updatedAt: Date()
        )
        writeSnapshot(snapshot)
        reloadWidgets()
    }
}
