/*
 * Purpose: Drives the drill sheet — loads the daily drill from a DrillEngine,
 *          grades the user's numeric/choice answer via DrillGrader, records the
 *          attempt (fire-and-forget) with the engine's sourceLabel, and updates
 *          the widget snapshot (drillDoneToday + streak-on-first-today).
 * Inputs: a DrillEngine, an AttemptRecorder; injectable snapshot read/write and
 *         widget-reload hooks (default the real SnapshotStore/WidgetCenter).
 * Outputs: an attempt POST (via the recorder), a widget-snapshot.json write.
 * Run: DrillViewModel(engine: DrillEngineProvider.make(...), recorder: rec)
 */

import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class DrillViewModel: Identifiable {
    enum Phase {
        case loading
        case ready(Drill)
        case answered(correct: Bool)
        case failed(String)
    }

    var phase: Phase = .loading
    var numericInput = ""
    var selectedChoice: Int?
    /// The loaded drill, retained so the answered state can show the correct
    /// value/choice and explanation (the .answered case carries only the Bool).
    private(set) var drill: Drill?
    /// The fire-and-forget attempt-record task, exposed so tests can await it.
    private(set) var recordTask: Task<Void, Never>?
    /// The streak after submit, for the answered-state streak line.
    private(set) var streakDays = 0

    private let engine: DrillEngine
    private let recorder: AttemptRecorder
    private let readSnapshot: () -> WidgetSnapshot?
    private let writeSnapshot: (WidgetSnapshot) -> Void
    private let reloadWidgets: () -> Void

    init(engine: DrillEngine,
         recorder: AttemptRecorder,
         readSnapshot: @escaping () -> WidgetSnapshot? = { SnapshotStore.read() },
         writeSnapshot: @escaping (WidgetSnapshot) -> Void = { SnapshotStore.write($0) },
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.engine = engine
        self.recorder = recorder
        self.readSnapshot = readSnapshot
        self.writeSnapshot = writeSnapshot
        self.reloadWidgets = reloadWidgets
    }

    func load() async {
        phase = .loading
        numericInput = ""
        selectedChoice = nil
        do {
            let drill = try await engine.dailyDrill()
            self.drill = drill
            phase = .ready(drill)
        } catch {
            phase = .failed("Couldn't load today's drill. Try again.")
        }
    }

    func submit() async {
        guard let drill = drill else { return }
        let correct = DrillGrader.grade(
            drill, numericInput: Double(numericInput), choiceIndex: selectedChoice
        )
        phase = .answered(correct: correct)

        // Fire-and-forget: recording never throws to the UI (queued for retry on
        // failure). Tagged with the engine's own source ("server" | "on_device").
        let source = engine.sourceLabel
        recordTask = Task { await recorder.record(drill: drill, source: source, correct: correct) }

        writeSnapshotAfterSubmit()
        reloadWidgets()
    }

    // Marks today's drill done; bumps the streak only on the first completion of
    // the day (drillDoneToday was false). Preserves the next-session/free fields
    // from the last dashboard-written snapshot.
    private func writeSnapshotAfterSubmit() {
        let current = readSnapshot()
        let wasDoneToday = current?.drillDoneToday ?? false
        let baseStreak = current?.streakDays ?? 0
        let newStreak = wasDoneToday ? baseStreak : baseStreak + 1
        let snapshot = WidgetSnapshot(
            streakDays: newStreak,
            drillDoneToday: true,
            nextSessionTitle: current?.nextSessionTitle,
            nextSessionOther: current?.nextSessionOther,
            nextSessionAt: current?.nextSessionAt,
            freeUntil: current?.freeUntil,
            updatedAt: Date()
        )
        streakDays = newStreak
        writeSnapshot(snapshot)
    }
}
