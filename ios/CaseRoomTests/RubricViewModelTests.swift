/*
 * Purpose: Unit tests for RubricViewModel — stubbed SessionService proving
 *          load populates the template/draft, scoring updates items, the
 *          debounce target (save()) sends the right body and updates
 *          gradePreview, and reveal forwards to SessionService.reveal.
 * Inputs: none (in-memory stub service).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubRubricSessionService: SessionService {
    var rubricResult: Result<RubricState, Error>
    var saveRubricResult: Result<Double, Error>
    var exhibitsResult: Result<[ExhibitMeta], Error> = .success([])

    private(set) var recordedSaveRubricIds: [Int] = []
    private(set) var recordedSaveRubricItems: [[String: RubricItemScore]] = []
    private(set) var recordedSaveRubricNotes: [String] = []
    private(set) var recordedRevealIds: [Int] = []
    private(set) var recordedRevealExhibitIds: [Int] = []

    init(rubric: RubricState) {
        self.rubricResult = .success(rubric)
        self.saveRubricResult = .success(rubric.gradePreview)
    }

    func rubric(id: Int) async throws -> RubricState {
        try rubricResult.get()
    }

    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double {
        recordedSaveRubricIds.append(id)
        recordedSaveRubricItems.append(items)
        recordedSaveRubricNotes.append(notesMd)
        return try saveRubricResult.get()
    }

    func reveal(id: Int, exhibitId: Int) async throws {
        recordedRevealIds.append(id)
        recordedRevealExhibitIds.append(exhibitId)
    }

    func exhibits(id: Int) async throws -> [ExhibitMeta] {
        try exhibitsResult.get()
    }

    // Unused by RubricViewModel — required by the SessionService protocol.
    func sessionDetail(id: Int) async throws -> SessionDetail { fatalError("not used") }
    func joinConfig(id: Int) async throws -> JoinConfig { fatalError("not used") }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { fatalError("not used") }
    func transition(id: Int, target: String) async throws -> SessionDetail { fatalError("not used") }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { fatalError("not used") }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { fatalError("not used") }
    func completeRecording(id: Int) async throws { fatalError("not used") }
    func finalize(id: Int, grade: Double?) async throws -> Finalized { fatalError("not used") }
}

final class RubricViewModelTests: XCTestCase {
    private func makeTemplateItems() -> [RubricTemplateItem] {
        [
            RubricTemplateItem(id: "structure", label: "Structuring & framework", dimension: "structure", maxPoints: 5),
            RubricTemplateItem(id: "quant", label: "Quantitative rigor", dimension: "quant", maxPoints: 5),
            RubricTemplateItem(id: "communication", label: "Communication", dimension: "communication", maxPoints: 5),
            RubricTemplateItem(id: "creativity", label: "Creativity", dimension: "creativity", maxPoints: 5),
            RubricTemplateItem(id: "recommendation", label: "Recommendation", dimension: "recommendation", maxPoints: 5),
        ]
    }

    private func makeRubric() -> RubricState {
        RubricState(
            templateItems: makeTemplateItems(),
            items: ["structure": RubricItemScore(points: 3, note: "Decent tree")],
            notesMd: "Started strong.",
            gradePreview: 3.0,
            grade: nil,
            finalizedAt: nil
        )
    }

    // MARK: - load

    func testLoadPopulatesTemplateItemsItemsAndGradePreview() async {
        let service = StubRubricSessionService(rubric: makeRubric())
        let viewModel = await RubricViewModel(sessionId: 42, service: service)

        await viewModel.load()

        let templateItems = await viewModel.templateItems
        let items = await viewModel.items
        let notesMd = await viewModel.notesMd
        let gradePreview = await viewModel.gradePreview

        XCTAssertEqual(templateItems.count, 5)
        XCTAssertEqual(templateItems.first?.id, "structure")
        XCTAssertEqual(items["structure"]?.points, 3)
        XCTAssertEqual(notesMd, "Started strong.")
        XCTAssertEqual(gradePreview, 3.0)
    }

    // MARK: - score

    func testScoreUpdatesItemPoints() async {
        let service = StubRubricSessionService(rubric: makeRubric())
        let viewModel = await RubricViewModel(sessionId: 42, service: service)
        await viewModel.load()

        await viewModel.score(itemId: "quant", points: 4)

        let items = await viewModel.items
        XCTAssertEqual(items["quant"]?.points, 4)
    }

    // MARK: - save (the debounce target, invoked directly — no wall-clock wait)

    func testSaveSendsUpdatedItemsAndNotesAndUpdatesGradePreview() async {
        let service = StubRubricSessionService(rubric: makeRubric())
        service.saveRubricResult = .success(4.6)
        let viewModel = await RubricViewModel(sessionId: 42, service: service)
        await viewModel.load()
        await viewModel.score(itemId: "quant", points: 4)
        await viewModel.setOverallNotes("Wrapping up.")

        let returnedGradePreview = await viewModel.save()
        await viewModel.cancelPendingAutosave()

        XCTAssertEqual(service.recordedSaveRubricIds, [42])
        let sentItems = service.recordedSaveRubricItems.last
        XCTAssertEqual(sentItems?["quant"]?.points, 4)
        XCTAssertEqual(sentItems?["structure"]?.points, 3)
        XCTAssertEqual(service.recordedSaveRubricNotes.last, "Wrapping up.")

        XCTAssertEqual(returnedGradePreview, 4.6)
        let gradePreview = await viewModel.gradePreview
        XCTAssertEqual(gradePreview, 4.6)
    }

    // MARK: - reveal

    func testRevealActionCallsServiceReveal() async {
        let service = StubRubricSessionService(rubric: makeRubric())
        let viewModel = await RubricViewModel(sessionId: 42, service: service)
        await viewModel.load()

        await viewModel.reveal(exhibitId: 7)

        XCTAssertEqual(service.recordedRevealIds, [42])
        XCTAssertEqual(service.recordedRevealExhibitIds, [7])
    }
}
