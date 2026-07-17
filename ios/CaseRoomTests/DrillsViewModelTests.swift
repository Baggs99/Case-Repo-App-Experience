/*
 * Purpose: Unit tests for DrillsViewModel — streakDay/submitted/beginLabel/
 *          hubPercentileLabel for submitted vs not-submitted gauntlets,
 *          16-bar trend derivation (left-pad when <16 points, last bar
 *          green), week-label suffix gating, the ordinal helper, and the
 *          C-14 board note derivation from group.pointsBehindNext.
 * Inputs: fake Gauntlet/Board services (no live network).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class DrillsViewModelTests: XCTestCase {

    // MARK: - Hero derivation

    func testNotSubmittedDerivesBeginLabelAndHidesPercentile() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        XCTAssertEqual(vm.streakDay, 12)
        XCTAssertFalse(vm.submitted)
        XCTAssertEqual(vm.beginLabel, "Begin today's set")
        XCTAssertNil(vm.hubPercentileLabel)
    }

    func testSubmittedDerivesSeeResultAndPercentileLabel() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: true, streak: 12, dailyPercentile: 66), trends: .fixture),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        XCTAssertTrue(vm.submitted)
        XCTAssertEqual(vm.beginLabel, "See today's result")
        XCTAssertEqual(vm.hubPercentileLabel, "66TH TODAY")
    }

    // MARK: - Trend bars

    func testTrendBarsIs16WithLastGreenWhenFullHistory() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture16),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        let bars = vm.trendBars
        XCTAssertEqual(bars.count, 16)
        XCTAssertTrue(bars.last!.isGreen)
        XCTAssertFalse(bars.first!.isPad)
        // Heights derive from score/6, clamped to a visible floor.
        for bar in bars {
            XCTAssertGreaterThan(bar.height, 0)
            XCTAssertLessThanOrEqual(bar.height, 1)
        }
    }

    func testTrendBarsLeftPadsWhenFewerThan16Points() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture(days: 5)),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        let bars = vm.trendBars
        XCTAssertEqual(bars.count, 16)
        XCTAssertEqual(bars.prefix(11).filter(\.isPad).count, 11)
        XCTAssertFalse(bars.last!.isPad)
        XCTAssertTrue(bars.last!.isGreen)
    }

    // MARK: - Week labels

    func testWeekLabelsAppendPercentileSuffixOnlyWhenSubmitted() async {
        let submitted = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: true, streak: 12, dailyPercentile: 66), trends: .fixture16),
            boardService: FakeDrillsBoardService(board: .fixture))
        await submitted.load()
        XCTAssertEqual(submitted.weekLabels.count, 4)
        XCTAssertEqual(submitted.weekLabels.last, "W29 — 66TH")

        let notSubmitted = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture16),
            boardService: FakeDrillsBoardService(board: .fixture))
        await notSubmitted.load()
        XCTAssertFalse(notSubmitted.weekLabels.last!.contains("—"))
    }

    // MARK: - Ordinal helper

    func testOrdinalHelper() {
        XCTAssertEqual(DrillsViewModel.ordinal(1), "1ST")
        XCTAssertEqual(DrillsViewModel.ordinal(2), "2ND")
        XCTAssertEqual(DrillsViewModel.ordinal(3), "3RD")
        XCTAssertEqual(DrillsViewModel.ordinal(11), "11TH")
        XCTAssertEqual(DrillsViewModel.ordinal(66), "66TH")
    }

    // MARK: - C-14 board note

    func testBoardNoteDerivesFromPointsBehindNextWhenSubmitted() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(
                gauntlet: .fixture(submitted: true, streak: 12, dailyPercentile: 66, pointsBehindNext: 4, rank: 6),
                trends: .fixture),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        XCTAssertEqual(vm.boardNote, "4 BEHIND №5")
    }

    func testBoardNoteOmittedWhenNotSubmitted() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        XCTAssertNil(vm.boardNote)
    }

    func testBoardEntriesExposedFromGroupBoard() async {
        let vm = DrillsViewModel(
            gauntletService: FakeDrillsGauntletService(gauntlet: .fixture(submitted: false, streak: 12), trends: .fixture),
            boardService: FakeDrillsBoardService(board: .fixture))
        await vm.load()
        XCTAssertEqual(vm.board?.entries.count, 10)
        XCTAssertEqual(vm.board?.group?.name, "C-14")
    }
}

// MARK: - Fixtures + fakes

private extension Gauntlet {
    static func fixture(submitted: Bool, streak: Int, dailyPercentile: Double? = nil,
                         pointsBehindNext: Int? = nil, rank: Int = 6) -> Gauntlet {
        let result: GauntletResult? = submitted
            ? GauntletResult(
                score: 5, slotsCorrect: 5, slots: 6, pointsAwarded: 40,
                dailyPercentile: dailyPercentile,
                group: GauntletGroup(groupId: 14, name: "C-14", rank: rank, points: 331, pointsBehindNext: pointsBehindNext),
                schoolPercentile: nil, vsPeersDelta: nil, weakSection: nil, streak: streak, setKey: "set-2026-07-16")
            : nil
        return Gauntlet(
            date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
            slots: (1...6).map { GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil) },
            streak: streak, submitted: submitted, result: result)
    }
}

private extension GauntletTrends {
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `count` consecutive days ending 2026-07-16 (a Thursday, W29), scores
    /// trending mildly upward.
    private static func trailingDays(_ count: Int) -> [TrendPoint] {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 16; comps.hour = 12
        let end = Calendar.current.date(from: comps)!
        return (0..<count).map { i in
            let date = Calendar.current.date(byAdding: .day, value: -(count - 1 - i), to: end)!
            return TrendPoint(date: isoDay.string(from: date), score: Double(2 + i % 5))
        }
    }

    /// 16 days of upward-trending scores.
    static let fixture16 = GauntletTrends(daily: trailingDays(16), byType: [], weakest: nil)

    static let fixture = fixture16

    static func fixture(days: Int) -> GauntletTrends {
        GauntletTrends(daily: trailingDays(days), byType: [], weakest: nil)
    }
}

private extension GroupBoard {
    static let fixture = GroupBoard(
        scope: "group", group: GroupRef(id: 14, name: "C-14"),
        entries: [
            BoardEntry(userId: 10, displayName: "R. Vance", photoKey: nil, points: 400, rank: 1, streak: 20),
            BoardEntry(userId: 11, displayName: "P. Nair", photoKey: nil, points: 380, rank: 2, streak: 18),
            BoardEntry(userId: 12, displayName: "K. Chen", photoKey: nil, points: 360, rank: 3, streak: 15),
            BoardEntry(userId: 13, displayName: "S. Park", photoKey: nil, points: 350, rank: 4, streak: 14),
            BoardEntry(userId: 14, displayName: "T. Becker", photoKey: nil, points: 335, rank: 5, streak: 13),
            BoardEntry(userId: 1, displayName: "Amara Osei", photoKey: nil, points: 331, rank: 6, streak: 12),
            BoardEntry(userId: 15, displayName: "J. Silva", photoKey: nil, points: 320, rank: 7, streak: 11),
            BoardEntry(userId: 16, displayName: "M. Lindqvist", photoKey: nil, points: 310, rank: 8, streak: 9),
            BoardEntry(userId: 17, displayName: "A. Kim", photoKey: nil, points: 300, rank: 9, streak: 7),
            BoardEntry(userId: 18, displayName: "D. Ortiz", photoKey: nil, points: 290, rank: 10, streak: 5),
        ])
}

private final class FakeDrillsGauntletService: GauntletService, @unchecked Sendable {
    let gauntletValue: Gauntlet
    let trendsValue: GauntletTrends
    init(gauntlet: Gauntlet, trends: GauntletTrends) {
        self.gauntletValue = gauntlet
        self.trendsValue = trends
    }
    func gauntlet() async throws -> Gauntlet { gauntletValue }
    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult {
        fatalError("DrillsViewModel never submits the gauntlet")
    }
    func trends() async throws -> GauntletTrends { trendsValue }
}

private final class FakeDrillsBoardService: BoardService, @unchecked Sendable {
    let boardValue: GroupBoard
    init(board: GroupBoard) { self.boardValue = board }
    func groupBoard() async throws -> GroupBoard { boardValue }
    func schoolBoard() async throws -> SchoolBoard { fatalError("Task 2 doesn't call schoolBoard()") }
    func globalBoard() async throws -> GlobalBoard { fatalError("Task 2 doesn't call globalBoard()") }
    func schoolsBoard() async throws -> SchoolsBoard { fatalError("Task 2 doesn't call schoolsBoard()") }
}
