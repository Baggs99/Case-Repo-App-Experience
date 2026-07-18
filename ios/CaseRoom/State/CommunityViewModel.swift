/*
 * Purpose: Backing state for the Community tab (canvas 6a phone / 2d tablet) —
 *          concurrently loads school standing, the user's groups, and their
 *          connections for the hero card + YOUR GROUPS + CONNECTIONS sections.
 *          Also owns `selectedGroupID` (Task 4, tablet 2d right pane) — the
 *          YOUR GROUPS selector's source of truth, mirroring LibraryViewModel.
 *          selectedID/selectedCase's selectedID-else-first-row pattern.
 * Inputs: CommunityService (default APIClient.shared).
 * Outputs: none (reads only; writes live in GroupPageViewModel/
 *          GroupCreateViewModel, later F8 tasks).
 * Run: owned by CommunityView; call load() from .task.
 */

import Foundation
import Observation

@Observable
@MainActor
final class CommunityViewModel {
    private(set) var schoolStanding: SchoolStanding?
    private(set) var groups: [GroupSummary] = []
    private(set) var connections: [Connection] = []
    // Distinguishes "never loaded" from "loaded, school standing is null"
    // (the latter is a legitimate dev-seed state, not a loading placeholder).
    private(set) var hasLoaded = false
    var errorMessage: String?

    // Task 4 (tablet 2d right pane): the YOUR GROUPS selector's raw
    // selection — nil until the first tap. `selectedGroup` below resolves
    // this against `groups`, defaulting to the first group.
    var selectedGroupID: Int?

    private let service: CommunityService
    private let isFixtureBacked: Bool

    init(service: CommunityService = APIClient.shared) {
        self.service = service
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: injects fixture data instead of hitting the network.
    /// `load()` is a deliberate no-op on this instance (mirrors
    /// HomeViewModel's fixture init) — a fixture-backed VM must never be
    /// silently overwritten by a live response.
    init(fixtureStanding: SchoolStanding, fixtureGroups: [GroupSummary], fixtureConnections: [Connection]) {
        self.service = NeverCalledCommunityService()
        self.isFixtureBacked = true
        self.schoolStanding = fixtureStanding
        self.groups = fixtureGroups
        self.connections = fixtureConnections
        self.hasLoaded = true
    }
    #endif

    func load() async {
        guard !isFixtureBacked else { return }
        errorMessage = nil
        do {
            async let s = service.schoolStanding()
            async let g = service.groups()
            async let c = service.connections()
            let standing = try await s
            let groups = try await g
            let connections = try await c
            self.schoolStanding = standing
            self.groups = groups
            self.connections = connections
        } catch {
            errorMessage = "Couldn't load Community. Try again."
        }
        hasLoaded = true
    }

    // Tablet fallback: the selected group if it's still in the loaded set,
    // else the first loaded group (mirrors LibraryViewModel.selectedCase).
    // nil only when there are no groups at all.
    var selectedGroup: GroupSummary? {
        if let selectedGroupID, let match = groups.first(where: { $0.id == selectedGroupID }) {
            return match
        }
        return groups.first
    }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatch is documented non-
/// interactive (simctl can't tap/type), so any call here is a misuse — fail
/// loudly instead of silently hitting the network.
private struct NeverCalledCommunityService: CommunityService {
    func connections() async throws -> [Connection] { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func groups() async throws -> [GroupSummary] { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func createGroup(name: String) async throws -> GroupSummary { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func group(id: Int) async throws -> GroupDetail { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func transferGroupAdmin(id: Int, userId: Int) async throws { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func groupProgress(id: Int) async throws -> [GroupProgressMember] { fatalError("fixture-backed CommunityViewModel must not call the network") }
    func schoolStanding() async throws -> SchoolStanding { fatalError("fixture-backed CommunityViewModel must not call the network") }
}
#endif
