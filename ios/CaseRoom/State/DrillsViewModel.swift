/*
 * Purpose: Backing state for the Drills hub (canvas 5b `dIsHub`) — concurrently
 *          loads the gauntlet, the 4-week trend series, and the C-14 group
 *          board, and derives the hero (streak/submitted/begin label/hub
 *          percentile), the 16-bar trend (I2 deviation: rendered from raw
 *          daily SCORE, not a daily-percentile series — see plan), the week
 *          labels, and the C-14 board note (I3: derived from
 *          `result.group.pointsBehindNext`, never fabricated).
 * Inputs: GauntletService/BoardService (default APIClient.shared).
 * Outputs: POST-free reads only (Task 2 never submits the gauntlet).
 * Run: owned by DrillsView; call load() from .task.
 */

import Foundation
import Observation

@Observable
@MainActor
final class DrillsViewModel {
    /// One trend bar (canvas 5b lines 936: 16 bars, opacity ramp, last green).
    struct TrendBar: Identifiable {
        let id = UUID()
        let height: Double     // 0...1 (score/6, clamped to a visible floor)
        let opacity: Double    // ink opacity for non-green bars; ignored when isGreen
        let isGreen: Bool      // the single last (most-recent) bar
        let isPad: Bool        // left-pad placeholder when <16 days of history
    }

    private(set) var gauntlet: Gauntlet?
    private(set) var trends: GauntletTrends?
    private(set) var board: GroupBoard?
    var errorMessage: String?

    private let gauntletService: GauntletService
    private let boardService: BoardService
    private let isFixtureBacked: Bool

    init(gauntletService: GauntletService = APIClient.shared,
         boardService: BoardService = APIClient.shared) {
        self.gauntletService = gauntletService
        self.boardService = boardService
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: injects fixture data instead of hitting the network
    /// (mirrors HomeViewModel's fixture init). `load()` is a deliberate no-op
    /// on this instance.
    init(fixtureGauntlet: Gauntlet, fixtureTrends: GauntletTrends, fixtureBoard: GroupBoard) {
        let never = NeverCalledDrillsService()
        self.gauntletService = never
        self.boardService = never
        self.isFixtureBacked = true
        self.gauntlet = fixtureGauntlet
        self.trends = fixtureTrends
        self.board = fixtureBoard
    }
    #endif

    func load() async {
        guard !isFixtureBacked else { return }
        errorMessage = nil
        do {
            async let g = gauntletService.gauntlet()
            async let t = gauntletService.trends()
            async let b = boardService.groupBoard()
            let gauntlet = try await g
            let trends = try await t
            let board = try await b
            self.gauntlet = gauntlet
            self.trends = trends
            self.board = board
        } catch {
            errorMessage = "Couldn't load Drills."
        }
    }

    // MARK: - Hero

    var streakDay: Int { gauntlet?.streak ?? 0 }
    var submitted: Bool { gauntlet?.submitted ?? false }

    var beginLabel: String { submitted ? "See today's result" : "Begin today's set" }

    /// "{ordinal} TODAY" (green) once submitted with a scored percentile; nil
    /// pre-submission and nil when the result has no percentile yet (no fiction).
    var hubPercentileLabel: String? {
        guard submitted, let pct = gauntlet?.result?.dailyPercentile else { return nil }
        return "\(Self.ordinal(Int(pct.rounded()))) TODAY"
    }

    // MARK: - Trend (I2 — deviation: score-derived bars under a percentile kicker)

    private static let barCount = 16

    /// Cold-start invariant: when `trends.daily` is empty, all 16 bars render
    /// as faint left-pads with no green last bar — harmless (no data yet),
    /// not an error state.
    var trendBars: [TrendBar] {
        let daily = trends?.daily ?? []
        let real = Array(daily.suffix(Self.barCount))
        let padCount = Self.barCount - real.count
        var bars: [TrendBar] = (0..<padCount).map { _ in
            TrendBar(height: 0.12, opacity: 0.10, isGreen: false, isPad: true)
        }
        for (offset, point) in real.enumerated() {
            let position = padCount + offset       // absolute slot 0..<16
            let isLast = position == Self.barCount - 1
            let height = min(max(point.score / 6, 0.12), 1.0)
            bars.append(TrendBar(height: height, opacity: Self.opacity(forPosition: position), isGreen: isLast, isPad: false))
        }
        return bars
    }

    /// Canvas-fixed recency ramp over the 16 absolute slots: 0-3 → .18,
    /// 4-7 → .28, 8-11 → .4, 12-14 → solid ink (1.0), 15 → green (opacity unused).
    private static func opacity(forPosition position: Int) -> Double {
        switch position {
        case 0..<4: return 0.18
        case 4..<8: return 0.28
        case 8..<12: return 0.4
        default: return 1.0
        }
    }

    /// "TREND — DAILY PERCENTILE, 4 WEEKS" kicker's four W-numbers, the last
    /// appending "— {ordinal(dailyPercentile)}" only when submitted AND a
    /// percentile is present.
    var weekLabels: [String] {
        let week = Self.isoWeek(for: latestTrendDate ?? Date())
        let base = (0..<4).map { "W\(week - 3 + $0)" }
        guard submitted, let pct = gauntlet?.result?.dailyPercentile else { return base }
        var labels = base
        labels[3] = "\(labels[3]) — \(Self.ordinal(Int(pct.rounded())))"
        return labels
    }

    private var latestTrendDate: Date? {
        guard let latest = trends?.daily.last?.date else { return nil }
        return Self.isoDayFormatter.date(from: latest)
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoWeek(for date: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.component(.weekOfYear, from: date)
    }

    // MARK: - Board (C-14, Task 2 ships the group scope; Task 3 adds the switcher)

    /// "{n} BEHIND №{rank-1}" derived from `result.group.pointsBehindNext`
    /// once submitted; nil pre-submission, when the field isn't present
    /// (I3 — never fabricated), or at rank 1 (there is no №0 to be behind).
    var boardNote: String? {
        guard submitted, let group = gauntlet?.result?.group, let behind = group.pointsBehindNext,
              group.rank > 1 else { return nil }
        return "\(behind) BEHIND №\(group.rank - 1)"
    }

    /// "COHORT {name} — WEEK {n}" — the group name from the live board (not
    /// hardcoded), the ISO week of today (not the trend series, which may lag).
    var boardHead: String {
        "COHORT \(board?.group?.name ?? "—") — WEEK \(Self.isoWeek(for: Date()))"
    }

    /// Identifies "your" row without a profile fetch (Task 2 doesn't load
    /// ProfileService): the submitted gauntlet's own `result.group` carries
    /// the caller's rank+points for today's C-14 board, which is a unique
    /// key into `entries`. Pre-submission there's no result, so no row is
    /// highlighted (honest: we have no other signal for "you" in the board).
    func isYourRow(_ entry: BoardEntry) -> Bool {
        guard let group = gauntlet?.result?.group else { return false }
        return entry.rank == group.rank && entry.points == group.points
    }

    // MARK: - Ordinal helper ("1ST".."66TH", shared with the board rows)

    static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        let suffix: String
        if (11...13).contains(mod100) {
            suffix = "TH"
        } else {
            switch n % 10 {
            case 1: suffix = "ST"
            case 2: suffix = "ND"
            case 3: suffix = "RD"
            default: suffix = "TH"
            }
        }
        return "\(n)\(suffix)"
    }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatch is documented non-
/// interactive, so any call here is a misuse — fail loudly instead of
/// silently hitting the network (mirrors HomeViewModel's NeverCalled pattern).
private struct NeverCalledDrillsService: GauntletService, BoardService {
    func gauntlet() async throws -> Gauntlet { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func trends() async throws -> GauntletTrends { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func groupBoard() async throws -> GroupBoard { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func schoolBoard() async throws -> SchoolBoard { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func globalBoard() async throws -> GlobalBoard { fatalError("fixture-backed DrillsViewModel must not call the network") }
    func schoolsBoard() async throws -> SchoolsBoard { fatalError("fixture-backed DrillsViewModel must not call the network") }
}
#endif
