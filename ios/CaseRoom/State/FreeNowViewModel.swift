/*
 * Purpose: Drives the Today tab's free-now toggle — sets/clears the user's
 *          "free to practice now" broadcast (60m default per DF-3), surfaces
 *          classmates currently free, and mirrors freeUntil into the widget
 *          snapshot (preserving streak/drill/session fields) on every change.
 * Inputs: AvailabilityService (default APIClient.shared); injectable snapshot
 *         read/write + widget-reload hooks (default SnapshotStore/WidgetCenter).
 * Outputs: a widget-snapshot.json write + free-now timeline reload per change.
 * Run: instantiated by TodayView; toggle()/refresh() from the toggle + .task.
 */

import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class FreeNowViewModel {
    var isFree = false
    var freeUntil: Date?
    var others: [FreeUser] = []
    var errorMessage: String?

    private let service: AvailabilityService
    private let readSnapshot: () -> WidgetSnapshot?
    private let writeSnapshot: (WidgetSnapshot) -> Void
    private let reloadWidgets: () -> Void

    init(service: AvailabilityService = APIClient.shared,
         readSnapshot: @escaping () -> WidgetSnapshot? = { SnapshotStore.read() },
         writeSnapshot: @escaping (WidgetSnapshot) -> Void = { SnapshotStore.write($0) },
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "CaseRoomFreeNow") }) {
        self.service = service
        self.readSnapshot = readSnapshot
        self.writeSnapshot = writeSnapshot
        self.reloadWidgets = reloadWidgets
    }

    /// Flips the broadcast: off -> on sets free for 60 minutes (DF-3 default);
    /// on -> off clears it.
    func toggle() async {
        if isFree {
            await clear()
        } else {
            await setFree(minutes: 60)
        }
    }

    /// Loads the current availability (own broadcast + classmates free now) and
    /// syncs the widget snapshot to server truth.
    func refresh() async {
        errorMessage = nil
        do {
            apply(try await service.availability())
        } catch {
            errorMessage = "Couldn't load availability. Try again."
        }
    }

    private func setFree(minutes: Int) async {
        errorMessage = nil
        do {
            apply(try await service.setFree(minutes: minutes))
        } catch {
            errorMessage = "Couldn't update your availability. Try again."
        }
    }

    private func clear() async {
        errorMessage = nil
        do {
            try await service.clearFree()
            isFree = false
            freeUntil = nil
            // DELETE returns 204 — leave `others` in place (clearing my own
            // broadcast doesn't change who else is free).
            updateSnapshot(freeUntil: nil)
        } catch {
            errorMessage = "Couldn't update your availability. Try again."
        }
    }

    private func apply(_ status: AvailabilityStatus) {
        freeUntil = status.freeUntil
        isFree = status.freeUntil != nil
        others = status.others
        updateSnapshot(freeUntil: status.freeUntil)
    }

    // Read-modify-write: another writer (the dashboard flow) owns streak/drill/
    // session fields, so carry them forward and only change freeUntil (Task 7
    // precedent), then reload just the free-now widget timeline.
    private func updateSnapshot(freeUntil: Date?) {
        let existing = readSnapshot()
        let snapshot = WidgetSnapshot(
            streakDays: existing?.streakDays ?? 0,
            drillDoneToday: existing?.drillDoneToday ?? false,
            nextSessionTitle: existing?.nextSessionTitle,
            nextSessionOther: existing?.nextSessionOther,
            nextSessionAt: existing?.nextSessionAt,
            freeUntil: freeUntil,
            updatedAt: Date()
        )
        writeSnapshot(snapshot)
        reloadWidgets()
    }
}
