/*
 * Purpose: Backing state for the Drills hub (canvas 5b `dIsHub`) — concurrently
 *          loads the gauntlet, the 4-week trend series, and the C-14 group
 *          board, and derives the hero (streak/submitted/begin label/hub
 *          percentile), the 16-bar trend (I2 deviation: rendered from raw
 *          daily SCORE, not a daily-percentile series — see plan), the week
 *          labels, and the C-14 board note (I3: derived from
 *          `result.group.pointsBehindNext`, never fabricated). Task 3 adds
 *          the 4-scope board switcher (C-14/WHARTON/GLOBAL/SCHOOLS):
 *          `boardScope` + `selectBoard(_:)` lazily loads + caches
 *          school/global/schools boards (C-14 stays eager from `load()`) and
 *          exposes the per-scope head/note/foot copy + percentile/decimal
 *          formatting `GauntletBoard` reads.
 * Inputs: GauntletService/BoardService (default APIClient.shared).
 * Outputs: POST-free reads only (Task 2/3 never submit the gauntlet).
 * Run: owned by DrillsView (via GauntletBoard); call load() from .task.
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
    /// on this instance. `boardScope` presets the active scope chip (Task 3
    /// `-F7Board` hatch); the three optional board fixtures pre-populate the
    /// scope caches so `GauntletBoard` never triggers `selectBoard(_:)`'s
    /// network path on a fixture-backed VM (which would `fatalError` via
    /// `NeverCalledDrillsService`) — a tap on any chip just reads an
    /// already-cached scope.
    init(fixtureGauntlet: Gauntlet, fixtureTrends: GauntletTrends, fixtureBoard: GroupBoard,
         boardScope: BoardScope = .c14,
         fixtureSchoolBoard: SchoolBoard? = nil,
         fixtureGlobalBoard: GlobalBoard? = nil,
         fixtureSchoolsBoard: SchoolsBoard? = nil) {
        let never = NeverCalledDrillsService()
        self.gauntletService = never
        self.boardService = never
        self.isFixtureBacked = true
        self.gauntlet = fixtureGauntlet
        self.trends = fixtureTrends
        self.board = fixtureBoard
        self.boardScope = boardScope
        self.schoolBoard = fixtureSchoolBoard
        self.globalBoard = fixtureGlobalBoard
        self.schoolsBoard = fixtureSchoolsBoard
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

    // MARK: - Board scope switcher (Task 3 — C-14/WHARTON/GLOBAL/SCHOOLS)

    /// The four board scopes (canvas 5b chips `C-14` `WHARTON` `GLOBAL`
    /// `SCHOOLS`). C-14 = `scope=group` (loaded eagerly by `load()`); the
    /// other three are lazily fetched + cached on first `selectBoard(_:)`.
    enum BoardScope: CaseIterable {
        case c14, wharton, global, schools

        var chipLabel: String {
            switch self {
            case .c14: return "C-14"
            case .wharton: return "WHARTON"
            case .global: return "GLOBAL"
            case .schools: return "SCHOOLS"
            }
        }
    }

    private(set) var boardScope: BoardScope = .c14
    private(set) var schoolBoard: SchoolBoard?
    private(set) var globalBoard: GlobalBoard?
    private(set) var schoolsBoard: SchoolsBoard?
    var boardErrorMessage: String?

    /// Switches the active scope and lazily loads + caches that scope's
    /// payload (a repeat select of an already-cached scope makes no network
    /// call — the "loader called once per scope" invariant tests assert).
    /// SCHOOLS also ensures `schoolBoard` is cached: B8's schools-vs-schools
    /// list carries no per-row "is this yours" flag, so identifying "yours"
    /// needs the caller's own school id, which only `scope=school` exposes
    /// (that IS "your school" per the B8 Interfaces contract) — an honest
    /// dependency, not a fabrication, and idempotent like every other cache.
    func selectBoard(_ scope: BoardScope) async {
        boardScope = scope
        boardErrorMessage = nil
        do {
            switch scope {
            case .c14:
                break
            case .wharton:
                if schoolBoard == nil { schoolBoard = try await boardService.schoolBoard() }
            case .global:
                if globalBoard == nil { globalBoard = try await boardService.globalBoard() }
            case .schools:
                if schoolBoard == nil { schoolBoard = try await boardService.schoolBoard() }
                if schoolsBoard == nil { schoolsBoard = try await boardService.schoolsBoard() }
            }
        } catch {
            boardErrorMessage = "Couldn't load board."
        }
    }

    /// Graceful ordinal for a possibly-nil percentile (WHARTON's "YOUR
    /// STANDING" row, GLOBAL's percentile hero) — nil → "—", never a crash
    /// or a fabricated number.
    func percentileLabel(_ percentile: Double?) -> String {
        guard let percentile else { return "—" }
        return Self.ordinal(Int(percentile.rounded()))
    }

    /// 1dp average — SCHOOLS/WHARTON's `avgMemberPercentile` is a population
    /// average, not a personal rank, so it renders as a plain decimal
    /// ("69.8"), never run through `ordinal(_:)`.
    static func decimal1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// SCHOOLS-list "yours" highlight — matched by school id against the
    /// caller's own school (from the cached `scope=school` board, per the
    /// selectBoard(.schools) dependency documented above).
    func isYourSchool(_ card: SchoolCard) -> Bool {
        guard let mine = schoolBoard?.school?.schoolId else { return false }
        return card.schoolId == mine
    }

    // MARK: - Per-scope head/note/foot copy (canvas tablet DC dScope logic,
    // verbatim; WEEK numbers are computed via `isoWeek`, not hardcoded, so
    // they never go stale — the rendered text matches the canvas literal for
    // any date the canvas's "WEEK 29" applies to).

    var currentBoardHead: String {
        switch boardScope {
        case .c14: return boardHead
        case .wharton: return "THE WHARTON SCHOOL — WEEK \(Self.isoWeek(for: Date()))"
        case .global: return "ALL PLAYERS — TODAY"
        case .schools: return "SCHOOL VS SCHOOL — WEEK \(Self.isoWeek(for: Date()))"
        }
    }

    var currentBoardNote: String? {
        switch boardScope {
        case .c14: return boardNote
        case .wharton: return "BY WEEKLY PERCENTILE"
        case .global: return "BY PERCENTILE"
        case .schools: return "AVG MEMBER PERCENTILE"
        }
    }

    var currentBoardFoot: String {
        switch boardScope {
        case .c14: return "Drill percentiles are public. Session grades stay private."
        case .wharton: return "Standing among verified Wharton members, by percentile. Head-counts stay private."
        case .global: return "Everyone who ran today's gauntlet, placed by percentile — never a head-count."
        case .schools: return "The average of member percentiles — never a head-count. Carry your school."
        }
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
