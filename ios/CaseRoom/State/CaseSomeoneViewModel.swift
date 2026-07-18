/*
 * Purpose: Drives the "Case someone" glass sheet (canvas 3b `sheetSomeone3`) —
 *          the interviewer-side verb. Loads the open-invite count + first
 *          invite line (candidates asking YOU to interview) and a best-effort
 *          interviewer log, and turns a scanned QR / typed short code into a
 *          paired session via pairClaim. Injectable CaseSomeoneService so tests
 *          never touch the network. Optional prefillCaseId/prefillCaseTitle
 *          carry the "case someone WITH THIS case" context from the F4 library.
 * Inputs: CaseSomeoneService (default APIClient.shared); optional prefill case;
 *         a `now` clock + Calendar; `feedbackAvg` (fixture-only continuity —
 *         the server has no "feedback quality" metric, see load()).
 * Outputs: none (in-memory state only; claimedSessionID/gatedRecapSessionID are
 *          consumed by the sheet to steer navigation).
 * Run: CaseSomeoneSheet(viewModel:) presents it; call load() from .task.
 */

import Foundation
import Observation

// The slice of the API the Case-someone sheet needs. APIClient conforms
// trivially — proposals()/sessions(scope:)/pairClaim(token:) all live on the
// actor (see APIClient.swift). pairClaim is the shared claim path, recap-gate
// wired; interviewing is never gated, but blockedByRecap is caught defensively.
protocol CaseSomeoneService {
    func proposals() async throws -> [Proposal]
    func sessions(scope: String) async throws -> [SessionSummary]
    func pairClaim(token: String) async throws -> Int
}

extension APIClient: CaseSomeoneService {}

@Observable
@MainActor
final class CaseSomeoneViewModel {
    /// "Case someone WITH THIS case" context, carried from the F4 library CTA.
    /// The canvas sheet has no case field, so the title only surfaces as a
    /// subtle muted context line (an additive prefill affordance).
    let prefillCaseId: Int?
    let prefillCaseTitle: String?

    // Open invites — candidates asking YOU to interview (received + candidate +
    // pending). Bound to the top row of the sheet.
    var openInviteCount = 0
    var firstInviteLine: String?
    var hasNew = false

    // "Your interviewer log" sub-line (best-effort — see load()).
    var interviewerLogLine: String?

    // Set on a successful pairClaim — the sheet dismisses and opens the existing
    // session (router.sessionTakeoverID). Set defensively on a recap gate
    // (interviewing is never gated, but handle it safely). Undesigned error line.
    var claimedSessionID: Int?
    var gatedRecapSessionID: Int?
    var errorMessage: String?

    private let service: CaseSomeoneService
    private let now: () -> Date
    private let calendar: Calendar
    private let feedbackAvg: Double?

    init(
        prefillCaseId: Int? = nil,
        prefillCaseTitle: String? = nil,
        service: CaseSomeoneService = APIClient.shared,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        feedbackAvg: Double? = nil
    ) {
        self.prefillCaseId = prefillCaseId
        self.prefillCaseTitle = prefillCaseTitle
        self.service = service
        self.now = now
        self.calendar = calendar
        self.feedbackAvg = feedbackAvg
    }

    /// Fetch proposals → open invites (received + candidate + pending); recent
    /// sessions → interviewer log. A single failure surfaces one undesigned
    /// error line; the sheet keeps its Cancel + Scan affordances either way.
    func load() async {
        errorMessage = nil
        do {
            async let proposalsResult = service.proposals()
            async let recentResult = service.sessions(scope: "recent")
            let proposals = try await proposalsResult
            let recentSessions = try await recentResult

            let invites = Self.openInvites(from: proposals)
            openInviteCount = invites.count
            hasNew = !invites.isEmpty
            firstInviteLine = invites.first.map {
                Self.inviteLine(for: $0, now: now(), calendar: calendar)
            }

            interviewerLogLine = Self.interviewerLogLine(
                from: recentSessions, now: now(), calendar: calendar, feedbackAvg: feedbackAvg
            )
        } catch {
            errorMessage = "Couldn't load your invites. Try again."
        }
    }

    /// Parse a scanned QR payload or a typed short code, then pairClaim. On
    /// success the interviewer is paired into the existing session; a recap gate
    /// (never expected for an interviewer seat) is caught defensively.
    func scanResult(_ raw: String) async {
        guard let code = Self.parseCode(raw) else {
            errorMessage = "That code didn't read. Try again."
            return
        }
        do {
            claimedSessionID = try await service.pairClaim(token: code)
        } catch CaseGateError.blockedByRecap(let sessionId) {
            gatedRecapSessionID = sessionId
        } catch {
            errorMessage = "Couldn't pair. Try again."
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Open invites = proposals a CANDIDATE sent YOU asking to be interviewed
    /// (direction received, fromRole candidate, state pending). Interviewer-role
    /// or sent proposals are excluded.
    static func openInvites(from proposals: [Proposal]) -> [Proposal] {
        proposals.filter {
            $0.direction == "received" && $0.fromRole == "candidate" && $0.state == "pending"
        }
    }

    /// "S. Park asks you to interview · tonight 21:30" — reuses CaseTabCopy's
    /// candidate-side label + a today-aware time suffix.
    static func inviteLine(for proposal: Proposal, now: Date, calendar: Calendar) -> String {
        let base = CaseTabCopy.pendingOfferLabel(fromName: proposal.fromName, fromRole: proposal.fromRole)
        guard let time = proposal.proposedTimes.first else { return base }
        let clock = timeFormatter.string(from: time)
        let suffix = calendar.isDate(time, inSameDayAs: now)
            ? "tonight \(clock)"
            : "\(weekdayFormatter.string(from: time)) \(clock)"
        return "\(base) · \(suffix)"
    }

    /// "2 cased this month" — count of interviewer-role sessions ended this
    /// month. The canvas's "· 4.7 avg feedback quality" segment is appended only
    /// when a feedbackAvg is supplied; the server exposes no feedback-quality
    /// metric, so the live path omits it (documented data gap).
    static func interviewerLogLine(
        from sessions: [SessionSummary], now: Date, calendar: Calendar, feedbackAvg: Double?
    ) -> String {
        let count = sessions.filter {
            $0.role == "interviewer"
                && ($0.endedAt.map { calendar.isDate($0, equalTo: now, toGranularity: .month) } ?? false)
        }.count
        var line = "\(count) cased this month"
        if let feedbackAvg {
            line += " · \(String(format: "%.1f", feedbackAvg)) avg feedback quality"
        }
        return line
    }

    /// Parse either a `caseroom://pair?code=<code>` URL or a bare short code.
    /// Returns nil for empty input or a caseroom URL missing its code.
    static func parseCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("caseroom:") {
            guard let components = URLComponents(string: trimmed),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else { return nil }
            return code
        }
        return trimmed
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

#if DEBUG
extension CaseSomeoneViewModel {
    /// Fixture VM for `-CaseFixtures` screenshots/Previews (canvas `sheetSomeone3`):
    /// one open invite (S. Park asks you to interview · tonight 21:30 · NEW) and
    /// the interviewer log "2 cased this month · 4.7 avg feedback quality". No
    /// network — the stub service returns canned data.
    static func fixture() -> CaseSomeoneViewModel {
        CaseSomeoneViewModel(service: FixtureCaseSomeoneService(), feedbackAvg: 4.7)
    }
}

/// Stub CaseSomeoneService seeded with the canvas persona — no network; the
/// received-proposals set mixes an interviewer-role ask (excluded) with the S.
/// Park candidate invite (the one open invite), and recent sessions carry two
/// interviewer-role rows this month so the log reads "2 cased this month".
final class FixtureCaseSomeoneService: CaseSomeoneService {
    func proposals() async throws -> [Proposal] { CaseFixtures.pendingReceived }

    func sessions(scope: String) async throws -> [SessionSummary] {
        guard scope == "recent" else { return [] }
        return [
            SessionSummary(id: 401, role: "interviewer", otherUser: "R. Vance",
                           caseTitle: "EV charging — size the German market",
                           scheduledAt: nil, state: "done", endedAt: Date(), grade: 4.8),
            SessionSummary(id: 402, role: "interviewer", otherUser: "S. Park",
                           caseTitle: "US grocer weighs a move into meal kits",
                           scheduledAt: nil, state: "done", endedAt: Date(), grade: 4.6),
        ]
    }

    func pairClaim(token: String) async throws -> Int { 999 }
}
#endif
