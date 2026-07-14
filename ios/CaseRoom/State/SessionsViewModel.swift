/*
 * Purpose: Drives the Sessions tab — proposals inbox + upcoming sessions,
 *          via injectable SessionsService/CalendarAdding so tests never
 *          touch the network or EKEventStore.
 * Inputs: SessionsService (default APIClient.shared), CalendarAdding
 *         (default EventKitCalendarWriter()).
 * Outputs: EKEvent creation as a side effect of accept(_:at:).
 * Run: instantiated by SessionsView; call load() from .task.
 */

import Foundation
import Observation

protocol SessionsService {
    func proposals() async throws -> [Proposal]
    func sessions(scope: String) async throws -> [SessionSummary]
    func acceptProposal(id: Int, scheduledAt: Date) async throws -> AcceptedSession
    func declineProposal(id: Int) async throws
}

extension APIClient: SessionsService {}

@Observable
final class SessionsViewModel {
    var proposals: [Proposal] = []
    var upcoming: [SessionSummary] = []
    var errorMessage: String?
    var calendarError: String?
    var isLoading = false

    private let service: SessionsService
    private let calendar: CalendarAdding

    init(service: SessionsService = APIClient.shared, calendar: CalendarAdding = EventKitCalendarWriter()) {
        self.service = service
        self.calendar = calendar
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let proposalsResult = service.proposals()
            async let upcomingResult = service.sessions(scope: "upcoming")
            proposals = try await proposalsResult
            upcoming = try await upcomingResult
        } catch {
            errorMessage = "Couldn't load sessions. Try again."
        }
    }

    func accept(_ proposal: Proposal, at chosenTime: Date) async {
        do {
            _ = try await service.acceptProposal(id: proposal.id, scheduledAt: chosenTime)
            proposals.removeAll { $0.id == proposal.id }
            upcoming = (try? await service.sessions(scope: "upcoming")) ?? upcoming
            do {
                try await calendar.add(
                    title: proposal.caseTitle, startDate: chosenTime, notes: "with \(proposal.fromName)"
                )
                calendarError = nil
            } catch {
                calendarError = "Accepted, but couldn't add to your calendar."
            }
        } catch {
            errorMessage = "Couldn't accept this proposal. Try again."
        }
    }

    func decline(_ proposal: Proposal) async {
        do {
            try await service.declineProposal(id: proposal.id)
            proposals.removeAll { $0.id == proposal.id }
        } catch {
            errorMessage = "Couldn't decline this proposal. Try again."
        }
    }
}
