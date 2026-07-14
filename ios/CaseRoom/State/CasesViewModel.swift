/*
 * Purpose: Drives the Cases tab — search text + difficulty filter -> results,
 *          via an injectable CasesService so tests can stub the network.
 * Inputs: user-entered query/difficulty; CasesService (default APIClient.shared).
 * Outputs: none (in-memory state only).
 * Run: instantiated by CasesListView; call load() from .task/.onChange.
 */

import Foundation
import Observation

protocol CasesService {
    func cases(query: CaseQuery) async throws -> [CaseSummary]
    func caseDetail(id: Int) async throws -> CaseDetail
}

extension APIClient: CasesService {}

@Observable
final class CasesViewModel {
    var results: [CaseSummary] = []
    var query: String = ""
    var difficulty: String?
    var errorMessage: String?
    var isLoading = false

    private let service: CasesService

    init(service: CasesService = APIClient.shared) {
        self.service = service
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let caseQuery = CaseQuery(q: trimmed.isEmpty ? nil : trimmed, difficulty: difficulty)
            results = try await service.cases(query: caseQuery)
        } catch {
            results = []
            errorMessage = "Couldn't load cases. Try again."
        }
    }
}
