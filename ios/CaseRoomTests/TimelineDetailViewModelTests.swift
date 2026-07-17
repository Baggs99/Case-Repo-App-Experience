/*
 * Purpose: Unit tests for TimelineDetailViewModel — spellOut/tag-label helpers,
 *          headline derivation, the passed-deadline prompt state machine (right
 *          outcome string posted per branch), no_offer reweight copy + the
 *          nil-focus kicker fallback, and addFirm's optimistic row.
 * Inputs: an injected fake TimelineService.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class TimelineDetailViewModelTests: XCTestCase {

    // MARK: - Pure helpers

    func testSpellOut() {
        XCTAssertEqual(TimelineDetailViewModel.spellOut(58), "Fifty-eight")
        XCTAssertEqual(TimelineDetailViewModel.spellOut(8), "Eight")
        XCTAssertEqual(TimelineDetailViewModel.spellOut(100), "100")
        XCTAssertEqual(TimelineDetailViewModel.spellOut(0), "Zero")
        XCTAssertEqual(TimelineDetailViewModel.spellOut(13), "Thirteen")
    }

    func testTagLabelMapping() {
        XCTAssertEqual(TimelineDetailViewModel.tagLabel("on_track"), "ON PACE")
        XCTAssertEqual(TimelineDetailViewModel.tagLabel("focus"), "PUSH QUANT")
        XCTAssertEqual(TimelineDetailViewModel.tagLabel("early"), "EARLY")
    }

    // MARK: - Headline / readiness derivation

    func testHeadlineUsesSoonestNonPassedFirm() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        XCTAssertEqual(vm.headlineDays, "Fifty-eight days.")
        XCTAssertEqual(vm.nextRiserName, "McKinsey")
    }

    func testReadinessFirmsExcludePassed() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        XCTAssertEqual(vm.readinessFirms.map(\.name), ["McKinsey", "BCG", "Bain"])
        XCTAssertFalse(vm.readinessFirms.contains { $0.name == "Roland Berger" })
    }

    func testPassedPromptFindsFirstShowablePassedFirm() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        XCTAssertEqual(vm.passedPrompt?.name, "Roland Berger")
    }

    // MARK: - Prompt state machine

    func testAnswerInterviewedNoPostsDidntInterview() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        await vm.answerInterviewed(false)
        XCTAssertEqual(svc.lastOutcome, "didnt_interview")
        XCTAssertEqual(svc.lastFirmId, 4)
        guard case .result(let result) = vm.promptStage else {
            return XCTFail("expected .result after answering No")
        }
        XCTAssertEqual(result.outcome, "didnt_interview")
        XCTAssertEqual(result.dropped, true)
    }

    func testAnswerInterviewedYesRevealsOutcomeButtons() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        await vm.answerInterviewed(true)
        XCTAssertEqual(vm.promptStage, .interviewed)
        XCTAssertNil(svc.lastOutcome)  // no network call yet
    }

    func testRecordOutcomePostsExactOutcomeStrings() async {
        for outcome in ["offer", "no_offer", "waiting"] {
            let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
            let vm = TimelineDetailViewModel(service: svc)
            await vm.load()
            await vm.answerInterviewed(true)
            await vm.recordOutcome(outcome)
            XCTAssertEqual(svc.lastOutcome, outcome)
            XCTAssertEqual(svc.lastFirmId, 4)
            guard case .result(let result) = vm.promptStage else {
                return XCTFail("expected .result for \(outcome)")
            }
            XCTAssertEqual(result.outcome, outcome)
        }
    }

    func testNoOfferStoresReweightAndFocusKicker() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        svc.resultToReturn = FirmResult(
            outcome: "no_offer", status: "rejected",
            reweight: Reweight(focusDimension: "Market sizing", suggestedDrillType: "mental_math", extraCases: [101, 205]),
            snoozeUntil: nil, resultRecordedAt: nil, dropped: nil)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        await vm.answerInterviewed(true)
        await vm.recordOutcome("no_offer")
        guard case .result(let result) = vm.promptStage, let reweight = result.reweight else {
            return XCTFail("expected a no_offer result with a reweight")
        }
        XCTAssertEqual(vm.noOfferBody(reweight),
                        "Noted, not dwelt on. The plan reweights tonight: quant drills daily and two extra cases before McKinsey.")
        XCTAssertEqual(vm.noOfferKicker(reweight), "DIAGNOSTIC UPDATED · FOCUS UNCHANGED: MARKET SIZING")
    }

    func testNoOfferKickerFallsBackWhenFocusDimensionIsNil() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        svc.resultToReturn = FirmResult(
            outcome: "no_offer", status: "rejected",
            reweight: Reweight(focusDimension: nil, suggestedDrillType: "market_sizing", extraCases: [1]),
            snoozeUntil: nil, resultRecordedAt: nil, dropped: nil)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        await vm.answerInterviewed(true)
        await vm.recordOutcome("no_offer")
        guard case .result(let result) = vm.promptStage, let reweight = result.reweight else {
            return XCTFail("expected a no_offer result with a reweight")
        }
        XCTAssertEqual(vm.noOfferKicker(reweight), "DIAGNOSTIC UPDATED")
    }

    func testDroppedBodyUsesNextRiserAndLowercasedSpellOut() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        XCTAssertEqual(vm.droppedBody, "Off the line it goes. Focus shifts fully to McKinsey — fifty-eight days.")
    }

    // MARK: - Add a firm

    func testAddFirmTracksAndAppendsSetDateRow() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        XCTAssertTrue(vm.addableChips.contains { $0.firmId == 5 })
        await vm.addFirm(5)
        XCTAssertEqual(svc.trackedFirmIds, [5])
        XCTAssertTrue(vm.addedRows.contains { $0.firmId == 5 })
        XCTAssertFalse(vm.addableChips.contains { $0.firmId == 5 })
    }

    func testAddFirmSetsErrorOnFailure() async {
        let svc = FakeTimelineService(detail: .fixture, catalog: .fixture)
        svc.failTrack = true
        let vm = TimelineDetailViewModel(service: svc)
        await vm.load()
        await vm.addFirm(5)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.addedRows.contains { $0.firmId == 5 })
    }
}

// MARK: - Fixtures + fake service

private extension TimelineDetail {
    static let fixture = TimelineDetail(
        asOf: "2026-07-16",
        readiness: TimelineReadiness(label: "needs_work", ready: false, focusDimension: "Market sizing",
                                      recentCaseCount: 5, threshold: 6.0, minCases: 3),
        firms: [
            TimelineFirmDetail(
                firmId: 1, name: "McKinsey", slug: "mckinsey", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-12", region: "Americas",
                                        isEstimate: false, daysRemaining: 58, passed: false),
                readinessTag: "on_track", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 2, name: "BCG", slug: "bcg", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-30", region: "Americas",
                                        isEstimate: false, daysRemaining: 76, passed: false),
                readinessTag: "focus", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 3, name: "Bain", slug: "bain", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-10-08", region: "Americas",
                                        isEstimate: true, daysRemaining: 84, passed: false),
                readinessTag: "early", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 4, name: "Roland Berger", slug: "roland-berger", status: "tracked", addedAt: "2026-05-01",
                deadline: FirmDeadline(cycleLabel: "Summer", deadlineDate: "2026-07-02", region: "Americas",
                                        isEstimate: false, daysRemaining: -14, passed: true),
                readinessTag: "on_track", prompt: FirmPrompt(show: true)),
        ])
}

private extension Array where Element == FirmCatalogEntry {
    static let fixture: [FirmCatalogEntry] = [
        FirmCatalogEntry(firmId: 1, name: "McKinsey", slug: "mckinsey", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 2, name: "BCG", slug: "bcg", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 3, name: "Bain", slug: "bain", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 4, name: "Roland Berger", slug: "roland-berger", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 5, name: "Deloitte", slug: "deloitte", tracked: false, nextDeadline: nil),
        FirmCatalogEntry(firmId: 6, name: "EY-Parthenon", slug: "ey-parthenon", tracked: false, nextDeadline: nil),
    ]
}

private final class FakeTimelineService: TimelineService, @unchecked Sendable {
    var detail: TimelineDetail
    var catalog: [FirmCatalogEntry]
    var resultToReturn: FirmResult?
    var failTrack = false

    var lastFirmId: Int?
    var lastOutcome: String?
    var trackedFirmIds: [Int] = []

    init(detail: TimelineDetail, catalog: [FirmCatalogEntry]) {
        self.detail = detail
        self.catalog = catalog
    }

    func timeline() async throws -> TimelineDetail { detail }
    func timelineFirms() async throws -> [FirmCatalogEntry] { catalog }

    func trackFirm(firmId: Int) async throws {
        if failTrack { throw APIError.server(500) }
        trackedFirmIds.append(firmId)
    }

    func untrackFirm(firmId: Int) async throws {}

    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult {
        lastFirmId = firmId
        lastOutcome = outcome
        if let resultToReturn { return resultToReturn }
        return FirmResult(outcome: outcome, status: nil, reweight: nil, snoozeUntil: nil,
                           resultRecordedAt: nil, dropped: outcome == "didnt_interview" ? true : nil)
    }
}
