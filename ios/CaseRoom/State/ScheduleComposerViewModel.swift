/*
 * Purpose: Drives the "Schedule later" composer glass sheet (canvas 3b
 *          `sheetLater3`) — Amara proposes to be cased LATER: pick WHO (a
 *          connection), WHEN (Now / 1h / Tonight 8pm / Pick a time), and the
 *          CASE (Interviewer decides ⟂ Request the top recommendation), then
 *          send a scheduled proposal (from_role "candidate"). Injectable
 *          ScheduleService so tests never touch the network; an injectable
 *          clock + Calendar make the WHEN quick-pick times deterministic.
 * Inputs: ScheduleService (default APIClient.shared); a `now` clock + Calendar.
 * Outputs: none (in-memory state only; `sent` + `toastMessage` steer the sheet).
 * Run: ScheduleComposerSheet(viewModel:) presents it; call load() from .task.
 */

import Foundation
import Observation

// The slice of the API the Schedule composer needs. APIClient conforms trivially
// — connections()/recommendations(exclude:)/sendScheduledProposal(...) all live
// on the actor (see APIClient.swift). Proposal-create is NOT recap-gated.
protocol ScheduleService {
    func connections() async throws -> [Connection]
    func recommendations(exclude: [Int]) async throws -> [Recommendation]
    func sendScheduledProposal(toUserId: Int, caseId: Int?, fromRole: String, proposedTimes: [Date]) async throws
}

extension APIClient: ScheduleService {}

@Observable
@MainActor
final class ScheduleComposerViewModel {
    /// A WHO chip — one per connection (id + display name).
    struct WhoChip: Identifiable, Equatable {
        let id: Int          // userId
        let name: String     // displayName
    }

    /// WHEN quick-picks — a fixed set with canvas-verbatim labels.
    enum WhenPick: CaseIterable, Equatable {
        case now, oneHour, tonight8pm, pickTime

        var label: String {
            switch self {
            case .now: return "Now"
            case .oneHour: return "1h"
            case .tonight8pm: return "Tonight 8pm"
            case .pickTime: return "Pick a time"
            }
        }
    }

    /// CASE options — "Interviewer decides" (case-less) ⟂ "Request: <rec title>"
    /// bound to a recommendation (canvas §2 "Interviewer decides ⟂ Request:[rec]").
    enum CaseOption: Identifiable, Equatable {
        case interviewerDecides
        case request(Recommendation)

        var id: String {
            switch self {
            case .interviewerDecides: return "interviewerDecides"
            case .request(let rec): return "request-\(rec.caseId)"
            }
        }

        /// The row label — "Interviewer decides" or "Request: <rec title>".
        var label: String {
            switch self {
            case .interviewerDecides: return "Interviewer decides"
            case .request(let rec): return "Request: \(rec.title)"
            }
        }
    }

    var who: [WhoChip] = []
    var selectedWhoID: Int?
    var caseOptions: [CaseOption] = []
    var selectedWhen: WhenPick?
    var selectedCase: CaseOption?
    /// Bound to the "Pick a time" DatePicker (only used when selectedWhen == .pickTime).
    var pickTime: Date
    var toastMessage: String?
    var errorMessage: String?
    /// Set on a successful send — the sheet dismisses.
    var sent = false

    private let service: ScheduleService
    private let now: () -> Date
    private let calendar: Calendar

    init(
        service: ScheduleService = APIClient.shared,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.service = service
        self.now = now
        self.calendar = calendar
        self.pickTime = now()
    }

    /// Loads WHO chips (connections) + the CASE options (Interviewer decides +
    /// the top recommendation as a Request row). A single failure surfaces one
    /// undesigned error line; the sheet keeps its Cancel affordance either way.
    func load() async {
        errorMessage = nil
        do {
            async let connectionsResult = service.connections()
            async let recsResult = service.recommendations(exclude: [])
            let connections = try await connectionsResult
            let recs = try await recsResult
            who = connections.map { WhoChip(id: $0.userId, name: $0.displayName) }
            caseOptions = [.interviewerDecides] + recs.prefix(1).map { CaseOption.request($0) }
        } catch {
            errorMessage = "Couldn't load. Try again."
        }
    }

    /// The proposed times derived from the WHEN quick-pick:
    ///   .now        → [now]
    ///   .oneHour    → [now + 1h]
    ///   .tonight8pm → today at 20:00 local (tomorrow 20:00 if 20:00 has passed)
    ///   .pickTime   → [the DatePicker value]
    /// Empty when nothing is picked yet.
    func proposedTimes() -> [Date] {
        let base = now()
        switch selectedWhen {
        case .now: return [base]
        case .oneHour: return [base.addingTimeInterval(3600)]
        case .tonight8pm: return [Self.tonight8pm(from: base, calendar: calendar)]
        case .pickTime: return [pickTime]
        case nil: return []
        }
    }

    /// Today at 20:00 local; if 20:00 has already passed, tomorrow at 20:00.
    static func tonight8pm(from now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 20
        components.minute = 0
        components.second = 0
        let today8 = calendar.date(from: components) ?? now
        if today8 <= now {
            return calendar.date(byAdding: .day, value: 1, to: today8) ?? today8
        }
        return today8
    }

    /// The Send button's enabled state — all three choices must be made.
    var canSend: Bool {
        selectedWhoID != nil && selectedWhen != nil && selectedCase != nil
    }

    /// Sends the scheduled proposal (from_role "candidate"). caseId is nil for
    /// "Interviewer decides", else the requested recommendation's caseId. On
    /// success: a "Proposal sent" toast + `sent` (the sheet dismisses).
    func send() async {
        guard let whoID = selectedWhoID, selectedWhen != nil, let caseOption = selectedCase else { return }
        let caseId: Int?
        switch caseOption {
        case .interviewerDecides: caseId = nil
        case .request(let rec): caseId = rec.caseId
        }
        do {
            try await service.sendScheduledProposal(
                toUserId: whoID, caseId: caseId, fromRole: "candidate", proposedTimes: proposedTimes()
            )
            toastMessage = "Proposal sent"
            sent = true
        } catch {
            errorMessage = "Couldn't send the proposal. Try again."
        }
    }
}

#if DEBUG
extension ScheduleComposerViewModel {
    /// Fixture VM for `-CaseFixtures` screenshots/Previews (canvas `sheetLater3`):
    /// WHO = S. Park / T. Becker / M. Lindqvist (§3), the "EV charging — size the
    /// German market" recommendation (RECS[0]) as the Request row, and default
    /// selections (S. Park · Tonight 8pm · Interviewer decides) so the shot shows
    /// a populated, ready-to-send composer. No network — a stub service backs it.
    static func fixture() -> ScheduleComposerViewModel {
        let viewModel = ScheduleComposerViewModel(service: FixtureScheduleService())
        viewModel.who = [
            WhoChip(id: 501, name: "S. Park"),
            WhoChip(id: 601, name: "T. Becker"),
            WhoChip(id: 701, name: "M. Lindqvist"),
        ]
        viewModel.caseOptions = [.interviewerDecides, .request(FixtureScheduleService.evChargingRec)]
        viewModel.selectedWhoID = 501
        viewModel.selectedWhen = .tonight8pm
        viewModel.selectedCase = .interviewerDecides
        return viewModel
    }
}

/// Stub ScheduleService seeded with the canvas persona — no network; send is a
/// canned success so the screenshot hatch never hits a live server.
final class FixtureScheduleService: ScheduleService {
    /// §3 RECS[0]: "EV charging — size the German market" (Stern 2024, case id 8).
    static let evChargingRec = Recommendation(
        caseId: 8, title: "EV charging — size the German market",
        caseType: "Market Sizing", difficulty: nil,
        why: nil, rule: nil
    )

    func connections() async throws -> [Connection] {
        [
            Connection(userId: 501, displayName: "S. Park", photoUrl: nil, bio: nil, freeNow: true, swapInvitePending: false),
            Connection(userId: 601, displayName: "T. Becker", photoUrl: nil, bio: nil, freeNow: false, swapInvitePending: false),
            Connection(userId: 701, displayName: "M. Lindqvist", photoUrl: nil, bio: nil, freeNow: false, swapInvitePending: false),
        ]
    }

    func recommendations(exclude: [Int]) async throws -> [Recommendation] { [Self.evChargingRec] }

    func sendScheduledProposal(toUserId: Int, caseId: Int?, fromRole: String, proposedTimes: [Date]) async throws {}
}
#endif
