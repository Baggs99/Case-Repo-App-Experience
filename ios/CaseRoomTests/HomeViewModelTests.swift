/*
 * Purpose: Unit tests for HomeViewModel — greeting-by-hour + empty-name,
 *          ordinal, heroTitle spellOut, cohort-footer derivation (found/not-
 *          found), Swap advances + excludes shown ids, diagnostic bar width +
 *          FOCUS match, timeline tag-label mapping, dateKicker format, the
 *          tablet LAST-NIGHT line/hidden-state, and the UPCOMING row's T-minus.
 * Inputs: fake Dashboard/Gauntlet/Board/Profile/Recommendation/Timeline/Sessions services.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class HomeViewModelTests: XCTestCase {

    // MARK: - Pure helpers

    func testDateKickerFormat() {
        // Local noon so the formatted day is timezone-independent. The canvas
        // kicker reads "WEDNESDAY, JULY 16" but that's persona fiction — the
        // live kicker computes the REAL weekday, and 2026-07-16 is a Thursday.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 16; comps.hour = 12
        let date = Calendar.current.date(from: comps)!
        XCTAssertEqual(HomeViewModel.dateKicker(for: date), "THURSDAY, JULY 16")
    }

    func testGreetingByHour() {
        XCTAssertEqual(HomeViewModel.greeting(hour: 6, displayName: "Amara Osei"), "Morning, Amara.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 11, displayName: "Amara Osei"), "Morning, Amara.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 12, displayName: "Amara Osei"), "Afternoon, Amara.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 16, displayName: "Amara Osei"), "Afternoon, Amara.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 17, displayName: "Amara Osei"), "Evening, Amara.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 23, displayName: "Amara Osei"), "Evening, Amara.")
    }

    func testGreetingEmptyOrNilNameOmitsComma() {
        XCTAssertEqual(HomeViewModel.greeting(hour: 9, displayName: nil), "Morning.")
        XCTAssertEqual(HomeViewModel.greeting(hour: 9, displayName: ""), "Morning.")
    }

    func testOrdinal1Through10() {
        let expected = ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH", "9TH", "10TH"]
        for (i, exp) in expected.enumerated() {
            XCTAssertEqual(HomeViewModel.ordinal(i + 1), exp)
        }
    }

    func testDimensionLabelTitleCasesFirstWordOnly() {
        XCTAssertEqual(HomeViewModel.dimensionLabel("market_sizing"), "Market sizing")
        XCTAssertEqual(HomeViewModel.dimensionLabel("structure"), "Structure")
        XCTAssertEqual(HomeViewModel.dimensionLabel("communication"), "Communication")
    }

    // MARK: - Hero

    func testHeroTitleSpellsOutDrillsAndMinutes() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertEqual(vm.heroTitle, "Six drills, twelve minutes.")
        XCTAssertEqual(vm.streakDay, 12)
        XCTAssertFalse(vm.submitted)
    }

    // MARK: - Cohort footer

    func testCohortFooterDerivationFromBoardFixture() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertFalse(vm.cohortFooterHidden)
        XCTAssertEqual(vm.cohortLine, "COHORT C-14 · 6TH OF 10")
        XCTAssertEqual(vm.behindLine, "8 BEHIND №5")
    }

    func testCohortFooterHiddenWhenMyEntryNotFound() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(ProfileDetail(
                id: 999, email: "nobody@x.com", displayName: "Nobody", bio: nil, linkedinUrl: nil, school: nil, photoUrl: nil)),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertTrue(vm.cohortFooterHidden)
    }

    func testCohortFooterHiddenWhenNoGroup() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(GroupBoard(scope: "group", group: nil, entries: [])),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertTrue(vm.cohortFooterHidden)
    }

    // MARK: - Diagnostic

    func testDiagnosticBarWidthAndFocusMatch() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        let bars = vm.diagnosticBars
        XCTAssertEqual(bars.map(\.label), ["Structure", "Communication", "Quant", "Market sizing"])
        XCTAssertEqual(bars[0].width, 0.82, accuracy: 0.001)
        XCTAssertEqual(bars[0].valueText, "8.2")
        XCTAssertFalse(bars[0].isFocus)
        XCTAssertTrue(bars[3].isFocus)
        XCTAssertEqual(vm.casesLine, "14 CASES")
    }

    // MARK: - Swap

    func testSwapAdvancesAndExcludesShownIds() async {
        let recSvc = FakeRecommendationService([.fixture2])
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: recSvc,
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertEqual(vm.currentRecommendation?.caseId, Recommendation.fixture1.caseId)
        await vm.swap()
        XCTAssertEqual(recSvc.lastExclude, [Recommendation.fixture1.caseId])
        XCTAssertEqual(vm.currentRecommendation?.caseId, Recommendation.fixture2.caseId)
    }

    // MARK: - Timeline block

    func testTimelineFirmsTagLabelMapping() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertEqual(vm.timelineFirms.map(\.name), ["McKinsey", "BCG", "Bain"])
        XCTAssertEqual(vm.timelineFirms.map(\.readiness), ["ON PACE", "PUSH QUANT", "EARLY"])
        XCTAssertEqual(vm.timelineFirms.map(\.onPace), [true, false, false])
        // Roland Berger is passed -> excluded from the Home timeline block.
        XCTAssertFalse(vm.timelineFirms.contains { $0.name == "Roland Berger" })
    }

    // MARK: - Tonight

    func testTonightHiddenWhenNoNextSession() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(DashboardStats(
                sessionsFinalized: 0, streakWeeks: 0, nextSession: nil)),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertTrue(vm.tonightHidden)
    }

    // MARK: - LAST NIGHT (tablet strip; from sessions(scope:"recent"))

    func testLastNightLineFormatsGradeAndOtherUser() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([
                SessionSummary(id: 9, role: "candidate", otherUser: "M. Lindqvist",
                                caseTitle: "Dental roll-up", scheduledAt: nil,
                                state: "completed", endedAt: Date(), grade: 7.2),
            ]))
        await vm.load()
        XCTAssertFalse(vm.lastNightHidden)
        XCTAssertEqual(vm.lastNightLine, "7.2 avg vs M. Lindqvist")
        XCTAssertEqual(vm.lastNightSessionId, 9)
    }

    func testLastNightHiddenWhenNoFinishedSession() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([
                SessionSummary(id: 10, role: "candidate", otherUser: "X", caseTitle: "Y",
                                scheduledAt: Date(), state: nil, endedAt: nil, grade: nil),
            ]))
        await vm.load()
        XCTAssertTrue(vm.lastNightHidden)
        XCTAssertEqual(vm.lastNightLine, "")
        XCTAssertNil(vm.lastNightSessionId)
    }

    func testLastNightHiddenWhenNoSessionsAtAll() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertTrue(vm.lastNightHidden)
    }

    func testLastNightPicksFirstSessionWithGrade() async {
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(.fixture),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 12)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([
                SessionSummary(id: 1, role: "candidate", otherUser: "A", caseTitle: "c1",
                                scheduledAt: nil, state: nil, endedAt: nil, grade: nil),
                SessionSummary(id: 2, role: "candidate", otherUser: "B", caseTitle: "c2",
                                scheduledAt: nil, state: "completed", endedAt: Date(), grade: 6.0),
            ]))
        await vm.load()
        XCTAssertEqual(vm.lastNightSessionId, 2)
        XCTAssertEqual(vm.lastNightLine, "6.0 avg vs B")
    }

    // MARK: - UPCOMING row (tablet; T-minus)

    func testTMinusLabelWithin24Hours() {
        let now = Date(timeIntervalSince1970: 0)
        let scheduled = now.addingTimeInterval(9 * 3600)
        XCTAssertEqual(HomeViewModel.tMinusLabel(scheduledAt: scheduled, now: now), "T-9H")
    }

    func testTMinusLabelHiddenAt24HoursOrMore() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertNil(HomeViewModel.tMinusLabel(scheduledAt: now.addingTimeInterval(24 * 3600), now: now))
    }

    func testTMinusLabelHiddenForPastSession() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(HomeViewModel.tMinusLabel(scheduledAt: Date(timeIntervalSince1970: 0), now: now))
    }

    func testTMinusLabelHiddenWhenNoScheduledAt() {
        XCTAssertNil(HomeViewModel.tMinusLabel(scheduledAt: nil, now: Date()))
    }

    func testUpcomingLineAndSubFromNextSession() async {
        let today6pm = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        let vm = HomeViewModel(
            dashboardService: FakeDashboardService(DashboardStats(
                sessionsFinalized: 0, streakWeeks: 0,
                nextSession: SessionSummary(
                    id: 5, role: "candidate", otherUser: "T. Becker",
                    caseTitle: "Dental roll-up M&A", scheduledAt: today6pm,
                    state: nil, endedAt: nil, grade: nil),
                streakDays: 13, drillDoneToday: false)),
            gauntletService: FakeGauntletService(.fixture(slots: 6, streak: 13)),
            boardService: FakeBoardService(.fixture),
            profileService: FakeProfileService(.fixture),
            recommendationService: FakeRecommendationService([]),
            timelineService: FakeTimelineServiceForHome(.fixture),
            sessionsService: FakeSessionsServiceForHome([]))
        await vm.load()
        XCTAssertEqual(vm.upcomingLine, "vs T. Becker · Dental roll-up M&A")
        XCTAssertEqual(vm.upcomingSub, "Today 18:00 · candidate")
    }
}

// MARK: - Fixtures + fakes

private extension DashboardStats {
    static let fixture = DashboardStats(
        sessionsFinalized: 3, streakWeeks: 2,
        nextSession: SessionSummary(
            id: 1, role: "candidate", otherUser: "M. Lindqvist",
            caseTitle: "Low-cost carrier enters the Nordic market",
            scheduledAt: Date(), state: nil, endedAt: nil, grade: nil),
        streakDays: 12, drillDoneToday: false,
        dimensionAverages: nil,
        recommendations: [.fixture1, .fixture2],
        diagnostic: DiagnosticStats(
            casesDone60D: 14,
            dimensions: [
                DimensionScore(dimension: "structure", avgScore: 8.2, samples: 14),
                DimensionScore(dimension: "communication", avgScore: 7.4, samples: 14),
                DimensionScore(dimension: "quant", avgScore: 6.8, samples: 14),
                DimensionScore(dimension: "market_sizing", avgScore: 5.1, samples: 14),
            ],
            strengths: [], weaknesses: [], focusDimension: "market_sizing",
            trend: DiagnosticTrend(recentAvg: nil, previousAvg: nil, delta: nil, direction: nil)),
        timeline: nil)
}

private extension Recommendation {
    static let fixture1 = Recommendation(
        caseId: 101, title: "EV charging — size the German market",
        caseType: "Market sizing", difficulty: "D3", why: nil, rule: nil)
    static let fixture2 = Recommendation(
        caseId: 205, title: "Airline loyalty program overhaul",
        caseType: "Profitability", difficulty: "D2", why: nil, rule: nil)
}

private extension Gauntlet {
    static func fixture(slots: Int, streak: Int) -> Gauntlet {
        Gauntlet(
            date: "2026-07-16", setKey: "k1", provisional: false,
            slots: (1...slots).map { GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil) },
            streak: streak, submitted: false, result: nil)
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
            BoardEntry(userId: 14, displayName: "T. Becker", photoKey: nil, points: 339, rank: 5, streak: 13),
            BoardEntry(userId: 1, displayName: "Amara Osei", photoKey: nil, points: 331, rank: 6, streak: 12),
            BoardEntry(userId: 15, displayName: "J. Silva", photoKey: nil, points: 320, rank: 7, streak: 11),
            BoardEntry(userId: 16, displayName: "M. Lindqvist", photoKey: nil, points: 310, rank: 8, streak: 9),
            BoardEntry(userId: 17, displayName: "A. Kim", photoKey: nil, points: 300, rank: 9, streak: 7),
            BoardEntry(userId: 18, displayName: "D. Ortiz", photoKey: nil, points: 290, rank: 10, streak: 5),
        ])
}

private extension ProfileDetail {
    static let fixture = ProfileDetail(
        id: 1, email: "amara.osei@wharton.upenn.edu", displayName: "Amara Osei",
        bio: "MBA '27", linkedinUrl: nil,
        school: SchoolRef(id: 1, name: "Wharton", domain: "wharton.upenn.edu"), photoUrl: nil)
}

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

private final class FakeDashboardService: DashboardService, @unchecked Sendable {
    var value: DashboardStats
    init(_ value: DashboardStats) { self.value = value }
    func dashboard() async throws -> DashboardStats { value }
}

private final class FakeGauntletService: GauntletService, @unchecked Sendable {
    var value: Gauntlet
    init(_ value: Gauntlet) { self.value = value }
    func gauntlet() async throws -> Gauntlet { value }
    func submitGauntlet(_ answers: [GauntletAttempt]) async throws -> GauntletResult {
        fatalError("HomeViewModel never submits the gauntlet")
    }
    func trends() async throws -> GauntletTrends {
        fatalError("HomeViewModel never calls trends()")
    }
}

private final class FakeBoardService: BoardService, @unchecked Sendable {
    var value: GroupBoard
    init(_ value: GroupBoard) { self.value = value }
    func groupBoard() async throws -> GroupBoard { value }
    func schoolBoard() async throws -> SchoolBoard {
        fatalError("HomeViewModel never calls schoolBoard()")
    }
    func globalBoard() async throws -> GlobalBoard {
        fatalError("HomeViewModel never calls globalBoard()")
    }
    func schoolsBoard() async throws -> SchoolsBoard {
        fatalError("HomeViewModel never calls schoolsBoard()")
    }
}

private final class FakeProfileService: ProfileService, @unchecked Sendable {
    var value: ProfileDetail
    init(_ value: ProfileDetail) { self.value = value }
    func profile() async throws -> ProfileDetail { value }
    func updateProfile(displayName: String?, bio: String?, linkedinUrl: String?) async throws -> ProfileDetail { value }
    func uploadProfilePhoto(data: Data, mime: String) async throws -> String { "" }
    func notificationSettings() async throws -> NotificationSettings {
        NotificationSettings(proposals: true, sessionReminders: true, feedback: true, freeNow: true, community: true)
    }
    func updateNotificationSettings(_ settings: NotificationSettings) async throws -> NotificationSettings { settings }
}

private final class FakeRecommendationService: RecommendationService, @unchecked Sendable {
    var recs: [Recommendation]
    var lastExclude: [Int]?
    init(_ recs: [Recommendation]) { self.recs = recs }
    func recommendations(exclude: [Int]) async throws -> [Recommendation] {
        lastExclude = exclude
        return recs
    }
}

private final class FakeTimelineServiceForHome: TimelineService, @unchecked Sendable {
    var value: TimelineDetail
    init(_ value: TimelineDetail) { self.value = value }
    func timeline() async throws -> TimelineDetail { value }
    func timelineFirms() async throws -> [FirmCatalogEntry] { [] }
    func trackFirm(firmId: Int) async throws {}
    func untrackFirm(firmId: Int) async throws {}
    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult {
        FirmResult(outcome: outcome, status: nil, reweight: nil, snoozeUntil: nil, resultRecordedAt: nil, dropped: nil)
    }
}

private final class FakeSessionsServiceForHome: RecentSessionsService, @unchecked Sendable {
    var value: [SessionSummary]
    init(_ value: [SessionSummary]) { self.value = value }
    func sessions(scope: String) async throws -> [SessionSummary] { value }
}
