/*
 * Purpose: Backing state for the group-create flow (avatar sheet "Administer
 *          a group" -> name input -> "YOU'RE THE ADMIN"). Client-side name
 *          validation (1-100 non-blank) is UX only — the server (POST
 *          /groups) is the authoritative 1-100-chars check.
 * Inputs: CommunityService (default APIClient.shared).
 * Outputs: none (create() writes `created`, which carries invite_code +
 *          role:"admin" straight from the pinned POST /groups response).
 * Run: owned by GroupCreateView; call create() from the primary button.
 */

import Foundation
import Observation

@Observable
@MainActor
final class GroupCreateViewModel {
    var name: String = ""
    private(set) var created: GroupSummary?
    var errorMessage: String?
    private(set) var isCreating = false

    private let service: CommunityService
    private let isFixtureBacked: Bool

    init(service: CommunityService = APIClient.shared) {
        self.service = service
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: pre-populates `created` so GroupCreateView renders the
    /// "YOU'RE THE ADMIN" success state with no network call. Mirrors
    /// CommunityViewModel/GroupPageViewModel's fixture-init pattern — create()
    /// is a deliberate no-op on this instance.
    init(fixtureCreated: GroupSummary) {
        self.service = NeverCalledGroupCreateService()
        self.isFixtureBacked = true
        self.created = fixtureCreated
    }
    #endif

    /// 1-100 non-blank (trimmed) — UX-only guard; the server is authoritative.
    var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
    }

    func create() async {
        guard !isFixtureBacked, isNameValid, !isCreating else { return }
        errorMessage = nil
        isCreating = true
        do {
            created = try await service.createGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = "Couldn't create the group. Try again."
        }
        isCreating = false
    }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatch is documented non-
/// interactive (simctl can't tap/type), so any call here is a misuse — fail
/// loudly instead of silently hitting the network.
private struct NeverCalledGroupCreateService: CommunityService {
    func connections() async throws -> [Connection] { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func groups() async throws -> [GroupSummary] { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func createGroup(name: String) async throws -> GroupSummary { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func group(id: Int) async throws -> GroupDetail { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func transferGroupAdmin(id: Int, userId: Int) async throws { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func groupProgress(id: Int) async throws -> [GroupProgressMember] { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
    func schoolStanding() async throws -> SchoolStanding { fatalError("fixture-backed GroupCreateViewModel must not call the network") }
}
#endif
