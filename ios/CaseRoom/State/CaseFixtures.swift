/*
 * Purpose: DEBUG-only fixture data for the Case tab (F3 Task 1) — the Design
 *          Decisions §3 persona (unread Ski-resort recap from T. Becker,
 *          pending T. Becker Thu 18:00 dental roll-up + S. Park tonight
 *          21:30, tonight 19:00 vs M. Lindqvist) so a `-CaseFixtures` hatch
 *          (wired by later F3 screen tasks) renders without a live server.
 *          Mirrors LibraryFixtures.swift/CommunityFixtures.swift's structure;
 *          case ids/titles reused from LibraryFixtures for continuity.
 * Inputs: none.
 * Outputs: CaseFixtures (recap/proposals/sessions), FixtureCaseTabService.
 * Run: a later F3 screen task wires -CaseFixtures the same way CasesListView
 *      reads -LibraryFixtures; this task only provides the data + stub service.
 */

#if DEBUG
import Foundation

enum CaseFixtures {
    /// Unread recap gate card (§3: "Ski resort profitability, T. Becker,
    /// 4.1/5, 'Structure held. The quant went soft in the middle — drill it
    /// before Thursday.'"). Same underlying session as LibraryFixtures'
    /// id-102 history row (case 6, "Ski resort: revenue up, profit down").
    static let gateRecap = RecapItem(
        sessionId: 102, caseId: 6, caseTitle: "Ski resort: revenue up, profit down",
        interviewerName: "T. Becker", grade: 4.1,
        finalizedAt: date("2026-07-12"), viewedAt: nil
    )

    /// §3 pending-received proposals: T. Becker's Thu 18:00 dental roll-up
    /// ask, and S. Park's tonight-21:30 ask (case-less — S. Park asks Amara
    /// to interview her; also FREE NOW per Community fixtures).
    static let pendingReceived: [Proposal] = [
        Proposal(
            id: 201, fromName: "T. Becker", fromRole: "interviewer", caseId: 4,
            caseTitle: "Private equity eyes a dental roll-up", caseType: "M&A", difficulty: "Hard",
            message: nil, proposedTimes: [nextWeekday(.thursday, hour: 18, minute: 0)],
            createdAt: date("2026-07-16"), direction: "received", state: "pending"
        ),
        Proposal(
            id: 202, fromName: "S. Park", fromRole: "candidate", caseId: nil, caseTitle: nil,
            caseType: nil, difficulty: nil, message: "Free now — mind interviewing?",
            proposedTimes: [tonight(hour: 21, minute: 30)],
            createdAt: Date(), direction: "received", state: "pending"
        ),
    ]

    /// One sent-and-awaiting proposal (fixture-only continuity data; not
    /// individually pinned by §3).
    static let sentAwaiting: [Proposal] = [
        Proposal(
            id: 203, fromName: "Amara Osei", fromRole: "candidate", caseId: 3,
            caseTitle: "Regional bank merger: the synergies", caseType: "M&A", difficulty: "Medium",
            message: nil, proposedTimes: [nextWeekday(.saturday, hour: 10, minute: 0)],
            createdAt: date("2026-07-15"), direction: "sent", state: "pending"
        ),
    ]

    /// §3: "Tonight 19:00: candidate vs M. Lindqvist (LBS) — 'Low-cost
    /// carrier enters the Nordic market'" (case 7, Kellogg 2019).
    static let nextUp = SessionSummary(
        id: 301, role: "candidate", otherUser: "M. Lindqvist",
        caseTitle: "Low-cost carrier enters the Nordic market",
        scheduledAt: tonight(hour: 19, minute: 0), state: "scheduled", endedAt: nil, grade: nil
    )

    /// One further-out upcoming row (fixture-only continuity data).
    static let upcoming: [SessionSummary] = [
        SessionSummary(
            id: 302, role: "interviewer", otherUser: "R. Vance",
            caseTitle: "EV charging — size the German market",
            scheduledAt: nextWeekday(.monday, hour: 17, minute: 0), state: "scheduled", endedAt: nil, grade: nil
        ),
    ]

    /// History rows — same finalized sessions as LibraryFixtures.sessions
    /// (minus the ski-resort one, which is still gating as `gateRecap` above).
    static let history: [SessionSummary] = [
        SessionSummary(id: 101, role: "candidate", otherUser: "M. Lindqvist",
                        caseTitle: "Low-cost carrier enters the Nordic market",
                        scheduledAt: nil, state: "done", endedAt: date("2026-07-16"), grade: 7.2),
        SessionSummary(id: 103, role: "candidate", otherUser: "S. Park",
                        caseTitle: "US grocer weighs a move into meal kits",
                        scheduledAt: nil, state: "done", endedAt: date("2026-07-08"), grade: 4.5),
        SessionSummary(id: 104, role: "candidate", otherUser: "guest",
                        caseTitle: "Regional bank merger: the synergies",
                        scheduledAt: nil, state: "done", endedAt: date("2026-06-30"), grade: 3.8),
    ]

    // MARK: F3 T6 — tablet tray's LIVE NOW board (canvas Tablet 1b): the same
    // free-right-now persona T3 already ships in GetCasedNowViewModel.fixture()
    // (S. Park · Wharton · 45 min free, J. Okafor · INSEAD · 20 min free) —
    // reused verbatim for continuity between the "Get cased now" sheet and the
    // tray board sitting right next to it.
    static let liveNow: [FreeUser] = [
        FreeUser(userId: 501, name: "S. Park", freeUntil: Date().addingTimeInterval(45 * 60)),
        FreeUser(userId: 502, name: "J. Okafor", freeUntil: Date().addingTimeInterval(20 * 60)),
    ]

    static let liveNowSchools: [Int: String] = [501: "Wharton", 502: "INSEAD"]

    private static func date(_ yyyyMMdd: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: yyyyMMdd) ?? Date()
    }

    /// Today at the given local hour/minute — "tonight" copy per §3.
    private static func tonight(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    /// The next upcoming occurrence of a weekday at the given local
    /// hour/minute (today counts as "next" only if the time hasn't passed).
    private static func nextWeekday(_ weekday: Weekday, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var searchDate = Date()
        for _ in 0..<8 {
            if calendar.component(.weekday, from: searchDate) == weekday.rawValue {
                var components = calendar.dateComponents([.year, .month, .day], from: searchDate)
                components.hour = hour
                components.minute = minute
                if let candidate = calendar.date(from: components), candidate > Date() {
                    return candidate
                }
            }
            searchDate = calendar.date(byAdding: .day, value: 1, to: searchDate) ?? searchDate
        }
        return searchDate
    }

    private enum Weekday: Int {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    }

    // MARK: F3 T6 — tablet July-17 day-advance (Decisions §7: "one day after
    // Part I; keep both frames' internal consistency... Mobile file stays on
    // July 16 — don't cross-pollinate"). Everything above this mark is the
    // UNCHANGED phone (July-16) persona.
    //
    // - Gate CLEARED: last night's Nordic session (M. Lindqvist, the phone's
    //   `nextUp`) is done — 7.2 avg, recap already rated 5/5 — so it no
    //   longer gates. `history` above already carries that finalized row
    //   (id 101, grade 7.2), reused verbatim.
    // - `upcoming` scope drops Nordic (it already happened) and keeps only
    //   the further-out R. Vance row (`CaseFixtures.upcoming`), so tablet's
    //   initial nextUp is R. Vance — until...
    // - ...T. Becker's dental-roll-up proposal is re-timed from the phone's
    //   "Thu 18:00" to tonight's "TODAY 18:00" per §7 — the accepted-state
    //   endpoint of "accept crosses columns" (Tablet 1b). Note: against the
    //   LIVE service, CaseTabViewModel.accept() genuinely produces this move
    //   (pendingReceived shrinks, refreshUpcoming() refetches and re-sorts —
    //   see testAcceptRemovesFromPendingReceivedRefreshesUpcomingAndAddsToCalendarOnce);
    //   FixtureCaseTabService's `sessions(scope:)` is static, though (matches
    //   the phone fixture's existing, pre-F3-T6 behavior), so tapping Accept
    //   under `-CaseFixtures` won't itself re-fetch T. Becker into nextUp —
    //   only the LIVE app demonstrates the full cross. The static screenshot
    //   still shows T. Becker correctly seated in PENDING pre-accept.
    static let tabletPendingReceived: [Proposal] = [
        Proposal(
            id: 201, fromName: "T. Becker", fromRole: "interviewer", caseId: 4,
            caseTitle: "Private equity eyes a dental roll-up", caseType: "M&A", difficulty: "Hard",
            message: nil, proposedTimes: [tonight(hour: 18, minute: 0)],
            createdAt: date("2026-07-16"), direction: "received", state: "pending"
        ),
        pendingReceived[1],   // S. Park's tonight-21:30 ask, unchanged.
    ]
}

/// Stub CaseTabService seeded with CaseFixtures — no network, and mutation
/// actions are no-ops/canned success so a screenshot hatch never crashes.
/// F3 T6: parameterized (defaults = the original phone/July-16 data
/// unchanged) so `CaseFixtures.makeTabletViewModel()` below can seed the
/// July-17 day-advance set without a second service type.
final class FixtureCaseTabService: CaseTabService {
    private let recap: RecapItem?
    private let pendingReceived: [Proposal]
    private let sentAwaiting: [Proposal]
    private let upcoming: [SessionSummary]
    private let history: [SessionSummary]

    init(
        recap: RecapItem? = CaseFixtures.gateRecap,
        pendingReceived: [Proposal] = CaseFixtures.pendingReceived,
        sentAwaiting: [Proposal] = CaseFixtures.sentAwaiting,
        upcoming: [SessionSummary] = [CaseFixtures.nextUp] + CaseFixtures.upcoming,
        history: [SessionSummary] = CaseFixtures.history
    ) {
        self.recap = recap
        self.pendingReceived = pendingReceived
        self.sentAwaiting = sentAwaiting
        self.upcoming = upcoming
        self.history = history
    }

    func recaps() async throws -> [RecapItem] { recap.map { [$0] } ?? [] }
    func proposals() async throws -> [Proposal] { pendingReceived + sentAwaiting }

    func sessions(scope: String) async throws -> [SessionSummary] {
        switch scope {
        case "upcoming": return upcoming
        case "recent": return history
        default: return []
        }
    }

    func acceptProposal(id: Int, scheduledAt: Date) async throws -> AcceptedSession {
        AcceptedSession(
            accepted: true, sessionId: 999,
            sessionUrl: "https://example.com/s/999", icsUrl: "https://example.com/s/999.ics"
        )
    }

    func declineProposal(id: Int) async throws {}
    func counterProposal(id: Int, times: [Date]) async throws {}

    // MARK: F3 T6 — tablet tray's LIVE NOW board; same persona in both the
    // phone and tablet fixture VMs (CaseFixtures.liveNow).
    func availability() async throws -> AvailabilityStatus {
        AvailabilityStatus(freeUntil: nil, others: CaseFixtures.liveNow)
    }

    func createNowInvite(toUserId: Int) async throws {}
}

/// No-op CalendarAdding for screenshot hatches — never touches real EventKit.
private struct NoOpCalendarWriter: CalendarAdding {
    func add(title: String, startDate: Date, notes: String?) async throws {}
}

extension CaseFixtures {
    /// Fixture-backed CaseTabViewModel for `-CaseFixtures` screenshots/Previews
    /// (phone, July-16 persona).
    static func makeViewModel() -> CaseTabViewModel {
        CaseTabViewModel(
            service: FixtureCaseTabService(), calendar: NoOpCalendarWriter(), schools: liveNowSchools
        )
    }

    /// F3 T6: fixture-backed CaseTabViewModel for the tablet's `-CaseFixtures`
    /// path (RootShell's `caseTabRoot`, `hSize == .regular`) — the July-17
    /// day-advance persona (see the F3 T6 mark above): gate cleared, T.
    /// Becker's dental-roll-up re-timed to today 18:00, Nordic dropped from
    /// upcoming (already in history). sentAwaiting/history are continuity
    /// data, unpinned by §7, so they're reused verbatim from the phone set.
    static func makeTabletViewModel() -> CaseTabViewModel {
        CaseTabViewModel(
            service: FixtureCaseTabService(
                recap: nil,
                pendingReceived: tabletPendingReceived,
                sentAwaiting: sentAwaiting,
                upcoming: upcoming,
                history: history
            ),
            calendar: NoOpCalendarWriter(),
            schools: liveNowSchools
        )
    }
}
#endif
