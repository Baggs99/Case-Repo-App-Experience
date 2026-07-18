/*
 * Purpose: Drives the Case tab (F3) — recap gate, proposal inbox (received/
 *          sent buckets), and upcoming/history sessions — via injectable
 *          CaseTabService/CalendarAdding so tests never touch the network or
 *          EKEventStore. Mirrors SessionsViewModel's shape; this VM
 *          supersedes it for the Case tab (F3 Task 2+ wires screens to it).
 * Inputs: CaseTabService (default APIClient.shared), CalendarAdding
 *         (default EventKitCalendarWriter()).
 * Outputs: EKEvent creation as a side effect of accept(_:at:)/addToCalendar(_:).
 * Run: instantiated by the Case tab screens (F3 Tasks 2-6); call load() from .task.
 */

import Foundation
import Observation

// Case-Tab data surface (contract sheet): recap gate feed, proposals,
// scoped sessions, and the accept/decline/counter actions. Backend supports
// only scope upcoming|recent — never "past".
protocol CaseTabService {
    func recaps() async throws -> [RecapItem]
    func proposals() async throws -> [Proposal]
    func sessions(scope: String) async throws -> [SessionSummary]
    func acceptProposal(id: Int, scheduledAt: Date) async throws -> AcceptedSession
    func declineProposal(id: Int) async throws
    func counterProposal(id: Int, times: [Date]) async throws
}

extension APIClient: CaseTabService {}

@Observable
final class CaseTabViewModel {
    // First unread recap — drives the gate card that blocks further
    // scheduling until closed (B3 recap gate).
    var gateRecap: RecapItem?
    var pendingReceived: [Proposal] = []
    var sentAwaiting: [Proposal] = []
    var nextUp: SessionSummary?
    var upcoming: [SessionSummary] = []
    var history: [SessionSummary] = []
    var errorMessage: String?
    var calendarError: String?
    // Set when an action 409s with CaseGateError.blockedByRecap — the
    // gated session id the caller must close a recap for before retrying.
    var gatedRecapSessionID: Int?
    var isLoading = false

    private let service: CaseTabService
    private let calendar: CalendarAdding

    init(service: CaseTabService = APIClient.shared, calendar: CalendarAdding = EventKitCalendarWriter()) {
        self.service = service
        self.calendar = calendar
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let recapsResult = service.recaps()
            async let proposalsResult = service.proposals()
            async let upcomingResult = service.sessions(scope: "upcoming")
            async let recentResult = service.sessions(scope: "recent")

            let recaps = try await recapsResult
            let proposals = try await proposalsResult
            let upcomingSessions = try await upcomingResult
            let recentSessions = try await recentResult

            gateRecap = recaps.first { $0.viewedAt == nil }
            bucketProposals(proposals)
            bucketUpcoming(upcomingSessions)
            history = recentSessions
        } catch {
            errorMessage = "Couldn't load your cases. Try again."
        }
    }

    private func bucketProposals(_ proposals: [Proposal]) {
        pendingReceived = proposals.filter { $0.direction == "received" && $0.state == "pending" }
        sentAwaiting = proposals.filter { $0.direction == "sent" && ($0.state == "pending" || $0.state == "countered") }
    }

    // nextUp = soonest by scheduledAt; upcoming = the rest.
    private func bucketUpcoming(_ sessions: [SessionSummary]) {
        let sorted = sessions.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
        nextUp = sorted.first
        upcoming = Array(sorted.dropFirst())
    }

    private func refreshUpcoming() async {
        if let sessions = try? await service.sessions(scope: "upcoming") {
            bucketUpcoming(sessions)
        }
    }

    // MARK: - Actions

    func accept(_ proposal: Proposal, at chosenTime: Date) async {
        do {
            _ = try await service.acceptProposal(id: proposal.id, scheduledAt: chosenTime)
            pendingReceived.removeAll { $0.id == proposal.id }
            await refreshUpcoming()
            do {
                try await calendar.add(
                    title: proposal.caseTitle ?? "Practice case", startDate: chosenTime,
                    notes: "with \(proposal.fromName)"
                )
                calendarError = nil
            } catch {
                calendarError = "Accepted, but couldn't add to your calendar."
            }
        } catch CaseGateError.blockedByRecap(let sessionId) {
            gatedRecapSessionID = sessionId
        } catch {
            errorMessage = "Couldn't accept this proposal. Try again."
        }
    }

    func decline(_ proposal: Proposal) async {
        do {
            try await service.declineProposal(id: proposal.id)
            pendingReceived.removeAll { $0.id == proposal.id }
        } catch CaseGateError.blockedByRecap(let sessionId) {
            gatedRecapSessionID = sessionId
        } catch {
            errorMessage = "Couldn't decline this proposal. Try again."
        }
    }

    // "New time" — recipient counters a pending proposal with alternate times.
    func counter(_ proposal: Proposal, times: [Date]) async {
        do {
            try await service.counterProposal(id: proposal.id, times: times)
        } catch CaseGateError.blockedByRecap(let sessionId) {
            gatedRecapSessionID = sessionId
        } catch {
            errorMessage = "Couldn't send new times. Try again."
        }
    }

    func addToCalendar(_ session: SessionSummary) async {
        guard let scheduledAt = session.scheduledAt else { return }
        do {
            try await calendar.add(title: session.caseTitle, startDate: scheduledAt, notes: "with \(session.otherUser)")
            calendarError = nil
        } catch {
            calendarError = "Couldn't add to your calendar."
        }
    }

    func clearGate() {
        gatedRecapSessionID = nil
    }
}
