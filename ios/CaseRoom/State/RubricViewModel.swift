/*
 * Purpose: Drives the interviewer's live screen — loads the rubric template +
 *          any existing draft plus exhibits, applies per-item point/note
 *          edits with a debounced (~800ms) autosave, and forwards exhibit
 *          reveals + the debrief transition to SessionService.
 * Inputs: sessionId; SessionService (default APIClient.shared).
 * Outputs: PUT /api/practice/{id}/rubric as a side effect of scoring/notes
 *          edits; POST .../reveals on reveal(exhibitId:); POST .../state on
 *          moveToDebrief(). No server timer — the stopwatch is view-local.
 * Run: instantiated by InterviewerLiveView; call load() from .task.
 */

import Foundation
import Observation

@Observable
@MainActor
final class RubricViewModel {
    let sessionId: Int

    var templateItems: [RubricTemplateItem] = []
    var items: [String: RubricItemScore] = [:]
    var notesMd: String = ""
    var gradePreview: Double = 0
    var exhibits: [ExhibitMeta] = []

    var isLoading = false
    var errorMessage: String?

    private let service: SessionService
    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelayNanoseconds: UInt64 = 800_000_000

    init(sessionId: Int, service: SessionService) {
        self.sessionId = sessionId
        self.service = service
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rubric = try await service.rubric(id: sessionId)
            templateItems = rubric.templateItems
            items = rubric.items
            notesMd = rubric.notesMd
            gradePreview = rubric.gradePreview
        } catch {
            errorMessage = "Couldn't load the rubric. Try again."
        }
        do {
            exhibits = try await service.exhibits(id: sessionId)
        } catch {
            // Exhibits are supplementary to scoring — a failure here
            // shouldn't block rubric editing.
        }
    }

    // MARK: - Edits (each schedules a debounced autosave)

    func score(itemId: String, points: Int) {
        let note = items[itemId]?.note ?? ""
        items[itemId] = RubricItemScore(points: points, note: note)
        scheduleAutosave()
    }

    func setNote(itemId: String, note: String) {
        let points = items[itemId]?.points ?? 0
        items[itemId] = RubricItemScore(points: points, note: note)
        scheduleAutosave()
    }

    func setOverallNotes(_ text: String) {
        notesMd = text
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.autosaveDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self.save()
        }
    }

    // MARK: - Save — the debounce target; public + directly callable so
    // tests can invoke the save path without waiting on wall-clock timing.

    @discardableResult
    func save() async -> Double {
        do {
            let preview = try await service.saveRubric(id: sessionId, items: items, notesMd: notesMd)
            gradePreview = preview
            return preview
        } catch {
            errorMessage = "Couldn't save the rubric. Try again."
            return gradePreview
        }
    }

    // MARK: - Exhibit reveal + debrief transition

    func reveal(exhibitId: Int) async {
        do {
            try await service.reveal(id: sessionId, exhibitId: exhibitId)
        } catch {
            errorMessage = "Couldn't release that exhibit. Try again."
        }
    }

    func moveToDebrief() async {
        do {
            _ = try await service.transition(id: sessionId, target: "debrief")
        } catch {
            errorMessage = "Couldn't move to debrief. Try again."
        }
    }
}
