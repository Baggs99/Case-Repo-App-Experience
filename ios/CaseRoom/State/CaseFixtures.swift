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
}

/// Stub CaseTabService seeded with CaseFixtures — no network, and mutation
/// actions are no-ops/canned success so a screenshot hatch never crashes.
final class FixtureCaseTabService: CaseTabService {
    func recaps() async throws -> [RecapItem] { [CaseFixtures.gateRecap] }
    func proposals() async throws -> [Proposal] { CaseFixtures.pendingReceived + CaseFixtures.sentAwaiting }

    func sessions(scope: String) async throws -> [SessionSummary] {
        switch scope {
        case "upcoming": return [CaseFixtures.nextUp] + CaseFixtures.upcoming
        case "recent": return CaseFixtures.history
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
}

/// No-op CalendarAdding for screenshot hatches — never touches real EventKit.
private struct NoOpCalendarWriter: CalendarAdding {
    func add(title: String, startDate: Date, notes: String?) async throws {}
}

extension CaseFixtures {
    /// Fixture-backed CaseTabViewModel for `-CaseFixtures` screenshots/Previews.
    static func makeViewModel() -> CaseTabViewModel {
        CaseTabViewModel(service: FixtureCaseTabService(), calendar: NoOpCalendarWriter())
    }
}
#endif
