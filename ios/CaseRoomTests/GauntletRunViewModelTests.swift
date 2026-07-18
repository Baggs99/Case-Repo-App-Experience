/*
 * Purpose: Unit tests for GauntletRunViewModel — the run→submit→result state
 *          machine. Covers: numeric-slot advance collects the signed value +
 *          a positive durationMs; the sign toggle produces a negative value;
 *          choice-slot tap records the choiceIndex (no value); last-slot advance
 *          triggers the submit → .result transition; GauntletError.alreadySubmitted
 *          recovers by re-fetching the embedded result; abandon submits nothing;
 *          a nil percentile result yields the graceful "—" label (no crash); and
 *          the drillType→kicker label map.
 * Inputs: a fake GauntletService + an injectable test clock (no live network,
 *         no runloop timer — autoTick off).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class GauntletRunViewModelTests: XCTestCase {

    // MARK: - Numeric slot capture

    func testNumericAdvanceCollectsSignedValueAndDuration() async {
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: FakeRunService(gauntlet: .numericFixture(count: 3), result: .fixture),
            preloaded: .numericFixture(count: 3), now: { clock.now }, autoTick: false)
        await vm.start()
        vm.numericInput = "12"
        clock.advance(2)                     // 2s on this slot
        await vm.advance()
        XCTAssertEqual(vm.answers.count, 1)
        XCTAssertEqual(vm.answers[0].slot, 1)
        XCTAssertEqual(vm.answers[0].value, 12)
        XCTAssertNil(vm.answers[0].choiceIndex)
        XCTAssertEqual(vm.answers[0].durationMs, 2000)
        XCTAssertGreaterThan(vm.answers[0].durationMs ?? 0, 0)
    }

    func testNumericSignToggleProducesNegativeValue() async {
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: FakeRunService(gauntlet: .numericFixture(count: 3), result: .fixture),
            preloaded: .numericFixture(count: 3), now: { clock.now }, autoTick: false)
        await vm.start()
        vm.numericInput = "5"
        vm.isNegative = true
        clock.advance(1)
        await vm.advance()
        XCTAssertEqual(vm.answers[0].value, -5)
    }

    // MARK: - Choice slot capture

    func testChoiceSlotRecordsChoiceIndexNoValue() async {
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: FakeRunService(gauntlet: .choiceFirstFixture, result: .fixture),
            preloaded: .choiceFirstFixture, now: { clock.now }, autoTick: false)
        await vm.start()
        XCTAssertFalse(vm.isNumericSlot)
        clock.advance(3)
        await vm.selectChoice(2)
        XCTAssertEqual(vm.answers.count, 1)
        XCTAssertEqual(vm.answers[0].choiceIndex, 2)
        XCTAssertNil(vm.answers[0].value)
        XCTAssertEqual(vm.answers[0].durationMs, 3000)
    }

    // MARK: - Submit on last slot

    func testLastSlotAdvanceTriggersSubmitAndResult() async {
        let service = FakeRunService(gauntlet: .numericFixture(count: 2), result: .fixture)
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: service, preloaded: .numericFixture(count: 2), now: { clock.now }, autoTick: false)
        await vm.start()
        vm.numericInput = "1"; clock.advance(1); await vm.advance()   // slot 1 → index 1
        vm.numericInput = "2"; clock.advance(1); await vm.advance()   // slot 2 (last) → submit
        XCTAssertEqual(service.submitCallCount, 1)
        XCTAssertEqual(vm.answers.count, 2)
        guard case .result(let result) = vm.phase else {
            return XCTFail("expected .result, got \(vm.phase)")
        }
        XCTAssertEqual(result, GauntletResult.fixture)
    }

    // MARK: - 409 recovery

    func testAlreadySubmittedRecoversEmbeddedResult() async {
        let embedded = GauntletResult.fixture
        let submittedGauntlet = Gauntlet.numericFixture(count: 1, submitted: true, result: embedded)
        let service = FakeRunService(
            gauntlet: submittedGauntlet, result: .fixture, submitError: GauntletError.alreadySubmitted)
        let clock = TestClock()
        // Fresh (not-submitted) gauntlet to run through; the service's gauntlet()
        // re-fetch returns the submitted one carrying the embedded result.
        let vm = GauntletRunViewModel(
            service: service, preloaded: .numericFixture(count: 1), now: { clock.now }, autoTick: false)
        await vm.start()
        vm.numericInput = "9"; clock.advance(1); await vm.advance()   // last slot → submit → 409 → recover
        XCTAssertEqual(service.submitCallCount, 1)
        XCTAssertEqual(service.gauntletCallCount, 1)                  // the recovery re-fetch
        guard case .result(let result) = vm.phase else {
            return XCTFail("expected recovered .result, got \(vm.phase)")
        }
        XCTAssertEqual(result, embedded)
    }

    // MARK: - Abandon

    func testAbandonDoesNotSubmit() async {
        let service = FakeRunService(gauntlet: .numericFixture(count: 3), result: .fixture)
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: service, preloaded: .numericFixture(count: 3), now: { clock.now }, autoTick: false)
        await vm.start()
        vm.numericInput = "1"; clock.advance(1); await vm.advance()   // partial run
        vm.stop()                                                     // abandon
        XCTAssertEqual(service.submitCallCount, 0)
        XCTAssertEqual(vm.answers.count, 1)                           // no phantom final answer
    }

    // MARK: - Percentile-nil graceful result

    func testNilPercentileResultRendersGracefulLabel() async {
        let vm = GauntletRunViewModel(preloadedResult: .fixtureNoPercentile, autoTick: false)
        await vm.start()
        guard case .result = vm.phase else { return XCTFail("expected .result") }
        XCTAssertEqual(vm.resultPercentileLabel, "—")
        XCTAssertEqual(vm.resultPercentileNumber, "—")
        XCTAssertEqual(vm.resultPercentileSuffix, "")
    }

    func testPreloadedResultOpensDirectlyInResultPhase() async {
        let vm = GauntletRunViewModel(preloadedResult: .fixture, preloadedElapsedSeconds: 252, autoTick: false)
        await vm.start()
        guard case .result = vm.phase else { return XCTFail("expected .result") }
        XCTAssertEqual(vm.resultPercentileLabel, "66TH")
        XCTAssertEqual(vm.resultPointsLabel, "+40 PTS")
        XCTAssertEqual(vm.resultCorrectLabel, "5/6 CORRECT")
        XCTAssertEqual(vm.resultGroupLabel, "3RD IN C-14 TODAY")
        XCTAssertEqual(vm.resultKicker, "PERCENTILE · TODAY'S GAUNTLET · 04:12")
        XCTAssertEqual(vm.weakCtaLabel, "Practice market sizing — 3 focused drills")
    }

    // MARK: - Kicker label map

    func testKickerLabelMapPerDrillType() async {
        let slots = [
            GauntletSlot(slot: 1, drillType: "mental_math", key: "k1", prompt: "p1", numbers: [], choices: nil),
            GauntletSlot(slot: 2, drillType: "market_sizing", key: "k2", prompt: "p2", numbers: [], choices: nil),
            GauntletSlot(slot: 3, drillType: "framework_recall", key: "k3", prompt: "p3", numbers: [], choices: nil),
            GauntletSlot(slot: 4, drillType: "some_new_type", key: "k4", prompt: "p4", numbers: [], choices: nil),
        ]
        let gauntlet = Gauntlet(date: "2026-07-16", setKey: "s", provisional: false,
                                slots: slots, streak: 1, submitted: false, result: nil)
        let clock = TestClock()
        let vm = GauntletRunViewModel(
            service: FakeRunService(gauntlet: gauntlet, result: .fixture),
            preloaded: gauntlet, now: { clock.now }, autoTick: false)
        await vm.start()
        XCTAssertEqual(vm.kicker, "MENTAL MATH — 1 OF 4")
        vm.numericInput = "1"; await vm.advance()
        XCTAssertEqual(vm.kicker, "MARKET SIZING — 2 OF 4")
        vm.numericInput = "1"; await vm.advance()
        XCTAssertEqual(vm.kicker, "STRUCTURES — 3 OF 4")
        vm.numericInput = "1"; await vm.advance()
        XCTAssertEqual(vm.kicker, "SOME NEW TYPE — 4 OF 4")   // caps fallback
    }

    // MARK: - Static helpers

    func testStaticTypeLabelAndFormatting() {
        XCTAssertEqual(GauntletRunViewModel.typeLabel("mental_math"), "MENTAL MATH")
        XCTAssertEqual(GauntletRunViewModel.typeLabel("market_sizing"), "MARKET SIZING")
        XCTAssertEqual(GauntletRunViewModel.typeLabel("framework_recall"), "STRUCTURES")
        XCTAssertEqual(GauntletRunViewModel.typeLabel("chart_read"), "CHART READ")
        XCTAssertEqual(GauntletRunViewModel.mmss(252), "04:12")
        XCTAssertEqual(GauntletRunViewModel.mmss(0), "00:00")
        XCTAssertEqual(GauntletRunViewModel.mmss(3661), "61:01")
        XCTAssertEqual(GauntletRunViewModel.ordinal(3), "3RD")
        XCTAssertEqual(GauntletRunViewModel.ordinal(66), "66TH")
    }

    func testKeypadSignedValueSemantics() {
        XCTAssertEqual(GauntletKeypad.signedValue(input: "12", isNegative: false), 12)
        XCTAssertEqual(GauntletKeypad.signedValue(input: "12", isNegative: true), -12)
        XCTAssertEqual(GauntletKeypad.signedValue(input: "3.5", isNegative: true), -3.5)
        XCTAssertNil(GauntletKeypad.signedValue(input: "", isNegative: false))
        XCTAssertNil(GauntletKeypad.signedValue(input: "abc", isNegative: false))
    }
}

// MARK: - Fixtures + fake

private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

private extension Gauntlet {
    static func numericFixture(count: Int, submitted: Bool = false, result: GauntletResult? = nil) -> Gauntlet {
        Gauntlet(
            date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
            slots: (1...count).map {
                GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil)
            },
            streak: 12, submitted: submitted, result: result)
    }

    static let choiceFirstFixture = Gauntlet(
        date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
        slots: [
            GauntletSlot(slot: 1, drillType: "market_sizing", key: "k1", prompt: "pick",
                         numbers: [], choices: ["A", "B", "C", "D"]),
            GauntletSlot(slot: 2, drillType: "mental_math", key: "k2", prompt: "p2", numbers: [], choices: nil),
        ],
        streak: 12, submitted: false, result: nil)
}

private extension GauntletResult {
    static let fixture = GauntletResult(
        score: 5, slotsCorrect: 5, slots: 6, pointsAwarded: 40,
        dailyPercentile: 66,
        group: GauntletGroup(groupId: 14, name: "C-14", rank: 3, points: 331, pointsBehindNext: 8),
        schoolPercentile: 71, vsPeersDelta: 3,
        weakSection: WeakSection(drillType: "market_sizing", label: "market sizing"),
        streak: 12, setKey: "set-2026-07-16")

    static let fixtureNoPercentile = GauntletResult(
        score: 4, slotsCorrect: 4, slots: 6, pointsAwarded: 20,
        dailyPercentile: nil, group: nil, schoolPercentile: nil, vsPeersDelta: nil,
        weakSection: nil, streak: 1, setKey: "set-2026-07-16")
}

private final class FakeRunService: GauntletService, @unchecked Sendable {
    let gauntletValue: Gauntlet
    let resultValue: GauntletResult
    let submitError: Error?
    private(set) var submitCallCount = 0
    private(set) var gauntletCallCount = 0

    init(gauntlet: Gauntlet, result: GauntletResult, submitError: Error? = nil) {
        self.gauntletValue = gauntlet
        self.resultValue = result
        self.submitError = submitError
    }

    func gauntlet() async throws -> Gauntlet { gauntletCallCount += 1; return gauntletValue }

    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult {
        submitCallCount += 1
        if let submitError { throw submitError }
        return resultValue
    }

    func trends() async throws -> GauntletTrends { fatalError("GauntletRunViewModel never calls trends()") }
}
