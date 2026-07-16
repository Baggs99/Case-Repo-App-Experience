/*
 * Purpose: Unit tests for DrillViewModel — stubbed engine/recorder proving load
 *          reaches .ready/.failed, numeric & choice grading paths, the attempt
 *          record carrying the engine's sourceLabel, and the drill-submit
 *          snapshot write (drillDoneToday + streak-on-first-today).
 * Inputs: none (in-memory stub engine, spy DrillService, injected snapshot hooks).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

private enum DrillTestError: Error { case boom }

private final class StubDrillEngine: DrillEngine {
    var result: Result<Drill, Error>
    let sourceLabel: String

    init(result: Result<Drill, Error>, sourceLabel: String) {
        self.result = result
        self.sourceLabel = sourceLabel
    }

    func dailyDrill() async throws -> Drill { try result.get() }
}

private actor SpyDrillService: DrillService {
    private(set) var recordCallCount = 0
    private(set) var recordedSource: String?
    private(set) var recordedDrillType: String?
    private(set) var recordedDrillKey: String?
    private(set) var recordedCorrect: Bool?

    func dailyDrill() async throws -> Drill { throw DrillTestError.boom }
    func templatePack() async throws -> Data { Data() }
    func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws {
        recordCallCount += 1
        recordedSource = source
        recordedDrillType = drillType
        recordedDrillKey = drillKey
        recordedCorrect = correct
    }
}

// Reference box so injected value-capturing closures mutate shared state without
// tripping @escaping mutable-capture rules under the @MainActor view model.
private final class SnapshotCapture {
    var written: WidgetSnapshot?
    var reloadCount = 0
}

final class DrillViewModelTests: XCTestCase {
    private func numericDrill() -> Drill {
        Drill(
            key: "mm_1", drillType: .mentalMath, prompt: "What is 12 x 8?", choices: nil,
            answer: DrillAnswer(kind: .numeric, value: 96, tolerancePct: 5, toleranceFactor: nil, correctIndex: nil),
            explanation: "12 x 8 = 96.", numbers: ["12", "8"]
        )
    }

    private func choiceDrill() -> Drill {
        Drill(
            key: "fr_1", drillType: .frameworkRecall, prompt: "Which framework fits pricing?",
            choices: ["Porter's Five Forces", "4Ps", "SWOT"],
            answer: DrillAnswer(kind: .choice, value: nil, tolerancePct: nil, toleranceFactor: nil, correctIndex: 1),
            explanation: "The 4Ps cover price.", numbers: []
        )
    }

    @MainActor
    private func makeViewModel(
        engine: DrillEngine,
        service: SpyDrillService = SpyDrillService(),
        capture: SnapshotCapture = SnapshotCapture(),
        current: WidgetSnapshot? = nil
    ) -> DrillViewModel {
        DrillViewModel(
            engine: engine,
            recorder: AttemptRecorder(service: service),
            readSnapshot: { current },
            writeSnapshot: { capture.written = $0 },
            reloadWidgets: { capture.reloadCount += 1 }
        )
    }

    @MainActor
    func testLoadSuccessSetsReady() async {
        let engine = StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server")
        let viewModel = makeViewModel(engine: engine)

        await viewModel.load()

        guard case .ready(let drill) = viewModel.phase else {
            return XCTFail("expected .ready, got \(viewModel.phase)")
        }
        XCTAssertEqual(drill.key, "mm_1")
    }

    @MainActor
    func testLoadFailureSetsFailedWithMessage() async {
        let engine = StubDrillEngine(result: .failure(DrillTestError.boom), sourceLabel: "server")
        let viewModel = makeViewModel(engine: engine)

        await viewModel.load()

        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("expected .failed, got \(viewModel.phase)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    @MainActor
    func testNumericSubmitWithinToleranceIsCorrect() async {
        let viewModel = makeViewModel(engine: StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server"))
        await viewModel.load()

        viewModel.numericInput = "96"
        await viewModel.submit()

        guard case .answered(let correct) = viewModel.phase else {
            return XCTFail("expected .answered, got \(viewModel.phase)")
        }
        XCTAssertTrue(correct)
    }

    @MainActor
    func testNumericSubmitOutsideToleranceIsIncorrect() async {
        let viewModel = makeViewModel(engine: StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server"))
        await viewModel.load()

        viewModel.numericInput = "40"
        await viewModel.submit()

        guard case .answered(let correct) = viewModel.phase else {
            return XCTFail("expected .answered, got \(viewModel.phase)")
        }
        XCTAssertFalse(correct)
    }

    @MainActor
    func testChoiceSubmitCorrectIndexIsCorrect() async {
        let viewModel = makeViewModel(engine: StubDrillEngine(result: .success(choiceDrill()), sourceLabel: "on_device"))
        await viewModel.load()

        viewModel.selectedChoice = 1
        await viewModel.submit()

        guard case .answered(let correct) = viewModel.phase else {
            return XCTFail("expected .answered, got \(viewModel.phase)")
        }
        XCTAssertTrue(correct)
    }

    @MainActor
    func testSubmitRecordsAttemptWithEngineSourceLabel() async {
        let service = SpyDrillService()
        let engine = StubDrillEngine(result: .success(numericDrill()), sourceLabel: "on_device")
        let viewModel = makeViewModel(engine: engine, service: service)
        await viewModel.load()

        viewModel.numericInput = "96"
        await viewModel.submit()
        await viewModel.recordTask?.value

        let count = await service.recordCallCount
        let source = await service.recordedSource
        let drillType = await service.recordedDrillType
        let correct = await service.recordedCorrect
        XCTAssertEqual(count, 1)
        XCTAssertEqual(source, "on_device")
        XCTAssertEqual(drillType, "mental_math")
        XCTAssertEqual(correct, true)
    }

    @MainActor
    func testSubmitWritesSnapshotAndIncrementsStreakWhenNotDoneToday() async {
        let capture = SnapshotCapture()
        let current = WidgetSnapshot(
            streakDays: 3, drillDoneToday: false, nextSessionTitle: "Widget Co",
            nextSessionOther: "Bob Dev", nextSessionAt: nil, freeUntil: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let viewModel = makeViewModel(
            engine: StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server"),
            capture: capture, current: current
        )
        await viewModel.load()

        viewModel.numericInput = "96"
        await viewModel.submit()

        XCTAssertEqual(capture.written?.drillDoneToday, true)
        XCTAssertEqual(capture.written?.streakDays, 4)
        XCTAssertEqual(capture.written?.nextSessionTitle, "Widget Co")
        XCTAssertEqual(capture.written?.nextSessionOther, "Bob Dev")
        XCTAssertEqual(capture.reloadCount, 1)
    }

    @MainActor
    func testSubmitDoesNotIncrementStreakWhenAlreadyDoneToday() async {
        let capture = SnapshotCapture()
        let current = WidgetSnapshot(
            streakDays: 5, drillDoneToday: true, nextSessionTitle: nil,
            nextSessionOther: nil, nextSessionAt: nil, freeUntil: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let viewModel = makeViewModel(
            engine: StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server"),
            capture: capture, current: current
        )
        await viewModel.load()

        viewModel.numericInput = "96"
        await viewModel.submit()

        XCTAssertEqual(capture.written?.drillDoneToday, true)
        XCTAssertEqual(capture.written?.streakDays, 5)
    }

    @MainActor
    func testSubmitInvokesOnAnsweredCallback() async {
        let viewModel = makeViewModel(engine: StubDrillEngine(result: .success(numericDrill()), sourceLabel: "server"))
        let calls = SnapshotCapture()
        viewModel.onAnswered = { calls.reloadCount += 1 }
        await viewModel.load()

        viewModel.numericInput = "96"
        await viewModel.submit()

        XCTAssertEqual(calls.reloadCount, 1)
    }
}
