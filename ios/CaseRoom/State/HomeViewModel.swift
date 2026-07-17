/*
 * Purpose: Backing state for the Home screen (canvas 3a phone / 2a tablet) —
 *          concurrently loads dashboard/gauntlet/groupBoard/profile/timeline/
 *          recent-sessions, and derives the greeting, today's-set hero (streak
 *          strip + cohort footer), tonight strip, diagnostic bars + recommendation
 *          swap, the timeline block's firm rows, and the tablet-only LAST-NIGHT/
 *          UPCOMING fields.
 * Inputs: DashboardService/GauntletService/BoardService/ProfileService/
 *         RecommendationService/TimelineService/RecentSessionsService (default
 *         APIClient.shared).
 * Outputs: POST-free reads only; recommendation Swap re-queries `exclude:`.
 * Run: owned by HomeView; call load() from .task.
 */

import Foundation
import Observation

protocol DashboardService {
    func dashboard() async throws -> DashboardStats
}
extension APIClient: DashboardService {}

// Just the one method Home needs from the existing /api/v1/sessions?scope=
// endpoint (SessionsViewModel's SessionsService covers the rest; this is a
// narrower seam so HomeViewModel doesn't pull in proposals/accept/decline).
protocol RecentSessionsService {
    func sessions(scope: String) async throws -> [SessionSummary]
}
extension APIClient: RecentSessionsService {}

@Observable
@MainActor
final class HomeViewModel {
    /// One streak-strip cell's fill state (14 cells: filled up to the streak,
    /// one "today" cell, the rest empty).
    enum StreakCellState { case filled, today, empty }

    struct DiagnosticBar: Identifiable {
        let id = UUID()
        let label: String
        let width: Double       // 0...1, avgScore/10
        let valueText: String   // "8.2"
        let isFocus: Bool
    }

    private(set) var dashboard: DashboardStats?
    private(set) var gauntlet: Gauntlet?
    private(set) var board: GroupBoard?
    private(set) var profile: ProfileDetail?
    private(set) var timelineDetail: TimelineDetail?
    private(set) var recentSessions: [SessionSummary] = []
    private(set) var currentRecommendation: Recommendation?
    private(set) var shownRecommendationIds: [Int] = []
    var errorMessage: String?

    private let dashboardService: DashboardService
    private let gauntletService: GauntletService
    private let boardService: BoardService
    private let profileService: ProfileService
    private let recommendationService: RecommendationService
    private let timelineService: TimelineService
    private let sessionsService: RecentSessionsService
    private let isFixtureBacked: Bool

    init(dashboardService: DashboardService = APIClient.shared,
         gauntletService: GauntletService = APIClient.shared,
         boardService: BoardService = APIClient.shared,
         profileService: ProfileService = APIClient.shared,
         recommendationService: RecommendationService = APIClient.shared,
         timelineService: TimelineService = APIClient.shared,
         sessionsService: RecentSessionsService = APIClient.shared) {
        self.dashboardService = dashboardService
        self.gauntletService = gauntletService
        self.boardService = boardService
        self.profileService = profileService
        self.recommendationService = recommendationService
        self.timelineService = timelineService
        self.sessionsService = sessionsService
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: injects fixture data instead of hitting the network.
    /// `load()` is a deliberate no-op on this instance (mirrors
    /// TimelineDetailViewModel's fixture init) — a fixture-backed VM must
    /// never be silently overwritten by a live response.
    init(fixtureDashboard: DashboardStats, fixtureGauntlet: Gauntlet, fixtureBoard: GroupBoard,
         fixtureProfile: ProfileDetail, fixtureTimeline: TimelineDetail,
         fixtureRecentSessions: [SessionSummary] = []) {
        let never = NeverCalledHomeService()
        self.dashboardService = never
        self.gauntletService = never
        self.boardService = never
        self.profileService = never
        self.recommendationService = never
        self.timelineService = never
        self.sessionsService = never
        self.isFixtureBacked = true
        self.dashboard = fixtureDashboard
        self.gauntlet = fixtureGauntlet
        self.board = fixtureBoard
        self.profile = fixtureProfile
        self.timelineDetail = fixtureTimeline
        self.recentSessions = fixtureRecentSessions
        self.currentRecommendation = fixtureDashboard.recommendations?.first
    }
    #endif

    func load() async {
        guard !isFixtureBacked else { return }
        errorMessage = nil
        do {
            async let d = dashboardService.dashboard()
            async let g = gauntletService.gauntlet()
            async let b = boardService.groupBoard()
            async let p = profileService.profile()
            async let t = timelineService.timeline()
            async let s = sessionsService.sessions(scope: "recent")
            let dashboard = try await d
            let gauntlet = try await g
            let board = try await b
            let profile = try await p
            let timelineDetail = try await t
            let recentSessions = try await s
            self.dashboard = dashboard
            self.gauntlet = gauntlet
            self.board = board
            self.profile = profile
            self.timelineDetail = timelineDetail
            self.recentSessions = recentSessions
            self.currentRecommendation = dashboard.recommendations?.first
        } catch {
            errorMessage = "Couldn't load your Home."
        }
    }

    // MARK: - Header

    var dateKicker: String { Self.dateKicker(for: Date()) }

    static func dateKicker(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM dd"
        return formatter.string(from: date).uppercased()
    }

    var greeting: String {
        Self.greeting(hour: Calendar.current.component(.hour, from: Date()), displayName: profile?.displayName)
    }

    /// "{Morning|Afternoon|Evening}, {firstName}." — an empty/nil name greets
    /// without a name (never "Morning, .").
    static func greeting(hour: Int, displayName: String?) -> String {
        let period: String
        switch hour {
        case ..<12: period = "Morning"
        case ..<17: period = "Afternoon"
        default: period = "Evening"
        }
        let firstName = displayName?.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? "\(period)." : "\(period), \(firstName)."
    }

    // MARK: - Hero (today's set)

    var streakDay: Int { gauntlet?.streak ?? 0 }
    var drillsCount: Int { gauntlet?.slots.count ?? 0 }
    var submitted: Bool { gauntlet?.submitted ?? false }
    /// DOCUMENTED estimate — minutes isn't in the gauntlet payload.
    var estMinutes: Int { drillsCount * 2 }

    /// "Six drills, twelve minutes." — sentence-leading count keeps spellOut's
    /// capital; the mid-sentence minutes count is lowercased.
    var heroTitle: String {
        "\(NumberWords.spellOut(drillsCount)) drills, \(NumberWords.spellOut(estMinutes).lowercased()) minutes."
    }

    var streakCells: [StreakCellState] {
        let filled = min(streakDay, 13)
        return (0..<14).map { i in
            if i < filled { return .filled }
            if i == filled { return .today }
            return .empty
        }
    }

    private var myBoardEntry: BoardEntry? {
        guard let profile else { return nil }
        return board?.entries.first { $0.userId == profile.id }
    }

    var cohortFooterHidden: Bool {
        myBoardEntry == nil || board?.group?.name == nil
    }

    var cohortLine: String {
        guard let entry = myBoardEntry, let name = board?.group?.name else { return "" }
        return "COHORT \(name) · \(Self.ordinal(entry.rank)) OF \(board?.entries.count ?? 0)"
    }

    var behindLine: String {
        guard let entry = myBoardEntry, let board,
              let ahead = board.entries.first(where: { $0.rank == entry.rank - 1 }) else { return "" }
        let gap = abs(ahead.points - entry.points)
        return "\(gap) BEHIND №\(entry.rank - 1)"
    }

    /// "1ST".."10TH" (uppercase suffix, canvas 3a "6TH OF 10").
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

    // MARK: - Tonight strip

    var tonightHidden: Bool { dashboard?.nextSession == nil }

    var tonightKicker: String {
        guard let session = dashboard?.nextSession, let at = session.scheduledAt else { return "" }
        let dayLabel = Calendar.current.isDateInToday(at) ? "TONIGHT" : Self.weekdayFormatter.string(from: at).uppercased()
        return "\(dayLabel) \(Self.timeFormatter.string(from: at)) · \(session.role.uppercased())"
    }

    var tonightLine: String {
        guard let session = dashboard?.nextSession else { return "" }
        return "vs \(session.otherUser) · \(session.caseTitle)"
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - LAST NIGHT (tablet-only dark strip; canvas 2a lines 85-88)

    /// Newest finished session (grade present) from sessions(scope:"recent").
    /// Deviation #2 (F2 plan): the canvas copy also carries "recap rated 5/5",
    /// but no GET exposes a recap star-rating — omitted here; backend follow-up.
    private var lastNightSession: SessionSummary? {
        recentSessions.first { $0.grade != nil }
    }

    var lastNightHidden: Bool { lastNightSession == nil }
    var lastNightSessionId: Int? { lastNightSession?.id }

    /// "{grade, 1dp} avg vs {otherUser}" — empty when no finished session.
    var lastNightLine: String {
        guard let session = lastNightSession, let grade = session.grade else { return "" }
        return "\(String(format: "%.1f", grade)) avg vs \(session.otherUser)"
    }

    // MARK: - UPCOMING (tablet-only; same next_session source as the tonight strip)

    /// "vs {otherUser} · {caseTitle}" — identical text to the phone tonight
    /// strip's line, just surfaced under a different tablet-only name.
    var upcomingLine: String { tonightLine }

    /// "{Today|Weekday} HH:mm · {role}". Deviation: the canvas persona sub-line
    /// also appends a third clause ("· quant-heavy on purpose") that has no API
    /// source (same pattern as the per-firm sub-detail deviation #3) — omitted.
    var upcomingSub: String {
        guard let session = dashboard?.nextSession, let at = session.scheduledAt else { return "" }
        let dayLabel = Calendar.current.isDateInToday(at) ? "Today" : Self.weekdayFormatter.string(from: at)
        return "\(dayLabel) \(Self.timeFormatter.string(from: at)) · \(session.role)"
    }

    /// "T-{hours}H" when next_session is within 24h (green); nil otherwise —
    /// hides the tag for past or >=24h-out sessions.
    var tMinus: String? {
        Self.tMinusLabel(scheduledAt: dashboard?.nextSession?.scheduledAt, now: Date())
    }

    static func tMinusLabel(scheduledAt: Date?, now: Date) -> String? {
        guard let scheduledAt else { return nil }
        let hours = scheduledAt.timeIntervalSince(now) / 3600
        guard hours >= 0, hours < 24 else { return nil }
        return "T-\(Int(hours.rounded(.up)))H"
    }

    // MARK: - Diagnostic

    var casesLine: String { "\(dashboard?.diagnostic?.casesDone60D ?? 0) CASES" }

    var diagnosticBars: [DiagnosticBar] {
        let diagnostic = dashboard?.diagnostic
        let focus = diagnostic?.focusDimension
        return (diagnostic?.dimensions ?? []).map { dim in
            DiagnosticBar(
                label: Self.dimensionLabel(dim.dimension),
                width: min(max(dim.avgScore / 10, 0), 1),
                valueText: String(format: "%.1f", dim.avgScore),
                isFocus: dim.dimension == focus)
        }
    }

    /// "market_sizing" -> "Market sizing" (title-case the first word only).
    static func dimensionLabel(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ").lowercased()
        guard let first = words.first else { return words }
        return first.uppercased() + words.dropFirst()
    }

    var recTitle: String { currentRecommendation?.title ?? "" }

    /// "{case_type} · {difficulty}" — provenance ("Stern 2024") isn't in the payload.
    var recMeta: String {
        [currentRecommendation?.caseType, currentRecommendation?.difficulty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    func swap() async {
        guard let current = currentRecommendation else { return }
        var shown = shownRecommendationIds
        shown.append(current.caseId)
        do {
            let recs = try await recommendationService.recommendations(exclude: shown)
            shownRecommendationIds = shown
            currentRecommendation = recs.first
        } catch {
            errorMessage = "Couldn't load another case."
        }
    }

    // MARK: - Timeline block

    var timelineFirms: [TimelineFirm] {
        (timelineDetail?.firms ?? [])
            .filter { $0.deadline != nil && $0.deadline?.passed != true }
            .compactMap { firm in
                guard let deadline = firm.deadline else { return nil }
                return TimelineFirm(
                    name: firm.name,
                    date: TimelineDetailViewModel.formattedDate(deadline.deadlineDate),
                    days: "\(deadline.daysRemaining)d",
                    readiness: TimelineDetailViewModel.tagLabel(firm.readinessTag),
                    onPace: firm.readinessTag == "on_track")
            }
    }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatch is documented non-
/// interactive (simctl can't tap/type), so any call here is a misuse — fail
/// loudly instead of silently hitting the network.
private struct NeverCalledHomeService: DashboardService, GauntletService, BoardService,
    ProfileService, RecommendationService, TimelineService, RecentSessionsService {
    func dashboard() async throws -> DashboardStats { fatalError("fixture-backed HomeViewModel must not call the network") }
    func sessions(scope: String) async throws -> [SessionSummary] { fatalError("fixture-backed HomeViewModel must not call the network") }
    func gauntlet() async throws -> Gauntlet { fatalError("fixture-backed HomeViewModel must not call the network") }
    func groupBoard() async throws -> GroupBoard { fatalError("fixture-backed HomeViewModel must not call the network") }
    func profile() async throws -> ProfileDetail { fatalError("fixture-backed HomeViewModel must not call the network") }
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail { fatalError("fixture-backed HomeViewModel must not call the network") }
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String { fatalError("fixture-backed HomeViewModel must not call the network") }
    func notificationSettings() async throws -> NotificationSettings { fatalError("fixture-backed HomeViewModel must not call the network") }
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings { fatalError("fixture-backed HomeViewModel must not call the network") }
    func recommendations(exclude: [Int]) async throws -> [Recommendation] { fatalError("fixture-backed HomeViewModel must not call the network") }
    func timeline() async throws -> TimelineDetail { fatalError("fixture-backed HomeViewModel must not call the network") }
    func timelineFirms() async throws -> [FirmCatalogEntry] { fatalError("fixture-backed HomeViewModel must not call the network") }
    func trackFirm(firmId: Int) async throws { fatalError("fixture-backed HomeViewModel must not call the network") }
    func untrackFirm(firmId: Int) async throws { fatalError("fixture-backed HomeViewModel must not call the network") }
    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult { fatalError("fixture-backed HomeViewModel must not call the network") }
}
#endif
