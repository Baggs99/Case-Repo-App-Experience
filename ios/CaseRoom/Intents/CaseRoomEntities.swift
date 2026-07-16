/*
 * Purpose: App Entities exposing cases, sessions, and proposals to Siri /
 *          Shortcuts / Spotlight, each with a query that reads through
 *          APIClient.shared behind an injectable EntityCatalog seam so the
 *          id->entity mapping and suggestions are unit-testable.
 * Inputs: EntityCatalog (default APIEntityCatalog -> APIClient.shared).
 * Outputs: none (queries return entity arrays; logged-out/network errors ->
 *          empty arrays, never thrown out of suggestedEntities()).
 * Run: referenced by CaseRoom's AppShortcuts / system entity resolution.
 */

import AppIntents
import Foundation

// Injectable data source for the entity queries. The default hits the shared
// API client; tests substitute an in-memory catalog.
protocol EntityCatalog: Sendable {
    func caseDetail(id: Int) async throws -> CaseDetail
    func cases() async throws -> [CaseSummary]
    func sessions() async throws -> [SessionSummary]
    func proposals() async throws -> [Proposal]
}

struct APIEntityCatalog: EntityCatalog {
    func caseDetail(id: Int) async throws -> CaseDetail {
        try await APIClient.shared.caseDetail(id: id)
    }
    func cases() async throws -> [CaseSummary] {
        try await APIClient.shared.cases(query: CaseQuery(limit: 5))
    }
    func sessions() async throws -> [SessionSummary] {
        try await APIClient.shared.sessions(scope: "upcoming")
    }
    func proposals() async throws -> [Proposal] {
        try await APIClient.shared.proposals()
    }
}

// MARK: - Case

struct CaseEntity: AppEntity {
    let id: Int
    let title: String
    let school: String?
    let difficulty: String?

    init(id: Int, title: String, school: String?, difficulty: String?) {
        self.id = id
        self.title = title
        self.school = school
        self.difficulty = difficulty
    }

    init(from summary: CaseSummary) {
        self.init(id: summary.id, title: summary.caseTitle,
                  school: summary.sourceSchool, difficulty: summary.difficulty)
    }

    init(from detail: CaseDetail) {
        self.init(id: detail.id, title: detail.caseTitle,
                  school: detail.sourceSchool, difficulty: detail.difficulty)
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Case" }
    static let defaultQuery = CaseEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        if let subtitle = Self.subtitle(school: school, difficulty: difficulty) {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
        }
        return DisplayRepresentation(title: "\(title)")
    }

    private static func subtitle(school: String?, difficulty: String?) -> String? {
        [school, difficulty?.capitalized].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

struct CaseEntityQuery: EntityQuery {
    var catalog: any EntityCatalog = APIEntityCatalog()

    func entities(for identifiers: [Int]) async throws -> [CaseEntity] {
        var results: [CaseEntity] = []
        for id in identifiers {
            if let detail = try? await catalog.caseDetail(id: id) {
                results.append(CaseEntity(from: detail))
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [CaseEntity] {
        guard let summaries = try? await catalog.cases() else { return [] }
        return summaries.prefix(5).map(CaseEntity.init(from:))
    }
}

// MARK: - Session

struct SessionEntity: AppEntity {
    let id: Int
    let caseTitle: String
    let otherUser: String
    let role: String
    let scheduledAt: Date?

    init(from summary: SessionSummary) {
        id = summary.id
        caseTitle = summary.caseTitle
        otherUser = summary.otherUser
        role = summary.role
        scheduledAt = summary.scheduledAt
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Session" }
    static let defaultQuery = SessionEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(caseTitle)", subtitle: "with \(otherUser)")
    }
}

struct SessionEntityQuery: EntityQuery {
    var catalog: any EntityCatalog = APIEntityCatalog()

    func entities(for identifiers: [Int]) async throws -> [SessionEntity] {
        let ids = Set(identifiers)
        guard let sessions = try? await catalog.sessions() else { return [] }
        return sessions.filter { ids.contains($0.id) }.map(SessionEntity.init(from:))
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        guard let sessions = try? await catalog.sessions() else { return [] }
        return sessions.prefix(5).map(SessionEntity.init(from:))
    }
}

// MARK: - Proposal

struct ProposalEntity: AppEntity {
    let id: Int
    let caseTitle: String
    let fromName: String

    init(from proposal: Proposal) {
        id = proposal.id
        caseTitle = proposal.caseTitle
        fromName = proposal.fromName
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Proposal" }
    static let defaultQuery = ProposalEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(caseTitle)", subtitle: "from \(fromName)")
    }
}

struct ProposalEntityQuery: EntityQuery {
    var catalog: any EntityCatalog = APIEntityCatalog()

    func entities(for identifiers: [Int]) async throws -> [ProposalEntity] {
        let ids = Set(identifiers)
        guard let proposals = try? await catalog.proposals() else { return [] }
        return proposals.filter { ids.contains($0.id) }.map(ProposalEntity.init(from:))
    }

    func suggestedEntities() async throws -> [ProposalEntity] {
        guard let proposals = try? await catalog.proposals() else { return [] }
        return proposals.prefix(5).map(ProposalEntity.init(from:))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
