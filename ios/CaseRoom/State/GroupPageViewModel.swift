/*
 * Purpose: Backing state for the group page (canvas 6a C-14 detail push) —
 *          loads GET /groups/{id}, derives isAdmin from the caller's own
 *          `members[]` row (the `group` object itself carries no role),
 *          and exposes the admin-only transfer-leadership + member-progress
 *          actions (defense-in-depth over the backend's 403 gate).
 * Inputs: CommunityService (default APIClient.shared); `currentUserId` — the
 *         seam for the isAdmin match. RootShell (which already reads
 *         SessionStore for the drill sheet, RootShell.swift ~:153) passes
 *         `sessionStore.user?.id` in at construction; tests pass a literal
 *         Int? with no SessionStore involved.
 * Outputs: none (writes — transfer/progress reload — live on this instance).
 * Run: owned by GroupPageView; call load(groupId:) from .task.
 */

import Foundation
import Observation

@Observable
@MainActor
final class GroupPageViewModel {
    private(set) var detail: GroupDetail?
    private(set) var leaderboard: [GroupLeaderboardEntry] = []
    private(set) var isAdmin = false
    private(set) var progress: [GroupProgressMember]?
    // Distinguishes "never loaded" from "loaded, detail is nil" (a 404
    // non-member or transport failure) — mirrors CommunityViewModel.hasLoaded.
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let service: CommunityService
    private let currentUserId: Int?
    private let isFixtureBacked: Bool
    // Remembered from the last successful load() so transfer()'s reload and
    // the admin progress load don't need the caller to re-pass groupId.
    private var groupId: Int?

    init(service: CommunityService = APIClient.shared, currentUserId: Int? = nil) {
        self.service = service
        self.currentUserId = currentUserId
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: injects fixture data instead of hitting the network.
    /// load()/transfer()/loadProgress() are deliberate no-ops on this instance
    /// (mirrors CommunityViewModel's fixture init) — a fixture-backed VM must
    /// never be silently overwritten by a live response.
    init(fixtureDetail: GroupDetail, fixtureIsAdmin: Bool, fixtureProgress: [GroupProgressMember]? = nil) {
        self.service = NeverCalledGroupPageService()
        self.currentUserId = nil
        self.isFixtureBacked = true
        self.detail = fixtureDetail
        self.leaderboard = fixtureDetail.leaderboard.sorted { $0.rank < $1.rank }
        self.isAdmin = fixtureIsAdmin
        self.progress = fixtureProgress
        self.groupId = fixtureDetail.group.id
        self.hasLoaded = true
    }
    #endif

    func load(groupId: Int) async {
        guard !isFixtureBacked else { return }
        self.groupId = groupId
        errorMessage = nil
        do {
            let detail = try await service.group(id: groupId)
            self.detail = detail
            self.leaderboard = detail.leaderboard.sorted { $0.rank < $1.rank }
            self.isAdmin = Self.computeIsAdmin(members: detail.members, currentUserId: currentUserId)
        } catch {
            self.detail = nil
            self.leaderboard = []
            self.isAdmin = false
            errorMessage = "Couldn't load this group. Try again."
        }
        hasLoaded = true
    }

    /// Admin-only (backend also 403s a member's attempt — this is
    /// defense-in-depth, not the enforcement point). Posts the transfer then
    /// reloads the group so the caller's own isAdmin/board reflect the new
    /// state — "optimistic" in that we don't hand-roll a rollback, a failed
    /// POST just surfaces errorMessage and leaves the prior state in place.
    func transfer(toUserId: Int) async {
        guard !isFixtureBacked, let groupId else { return }
        errorMessage = nil
        do {
            try await service.transferGroupAdmin(id: groupId, userId: toUserId)
            await load(groupId: groupId)
        } catch {
            errorMessage = "Couldn't transfer leadership. Try again."
        }
    }

    /// Admin-only; a no-op guard for non-admins (defense-in-depth alongside
    /// the view's own isAdmin gate and the backend's 403).
    func loadProgress(groupId: Int) async {
        guard !isFixtureBacked, isAdmin else { return }
        do {
            progress = try await service.groupProgress(id: groupId)
        } catch {
            errorMessage = "Couldn't load member progress."
        }
    }

    // MARK: - Pure helpers (unit-testable without a service/VM instance)

    /// GET /groups/{id} pins isAdmin to the caller's own `members[]` row —
    /// the `group` object carries no role. No match (member left, or the
    /// caller id is nil) is not-admin, never a crash.
    static func computeIsAdmin(members: [GroupMember], currentUserId: Int?) -> Bool {
        guard let currentUserId else { return false }
        return members.first(where: { $0.userId == currentUserId })?.role == "admin"
    }

    /// TOP FIVE ADVANCE split: ranks 1–5 above the divider, the rest (greyed/
    /// demoted) below. Assumes `leaderboard` is already rank-sorted (load()
    /// guarantees this; the static form re-sorts defensively for callers that
    /// hand it a raw API-order array).
    static func topFiveSplit(_ leaderboard: [GroupLeaderboardEntry]) -> (top: [GroupLeaderboardEntry], rest: [GroupLeaderboardEntry]) {
        let sorted = leaderboard.sorted { $0.rank < $1.rank }
        return (Array(sorted.prefix(5)), Array(sorted.dropFirst(5)))
    }

    var topFive: [GroupLeaderboardEntry] { Self.topFiveSplit(leaderboard).top }
    var restOfBoard: [GroupLeaderboardEntry] { Self.topFiveSplit(leaderboard).rest }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatch is documented non-
/// interactive (simctl can't tap/type), so any call here is a misuse — fail
/// loudly instead of silently hitting the network.
private struct NeverCalledGroupPageService: CommunityService {
    func connections() async throws -> [Connection] { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func groups() async throws -> [GroupSummary] { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func createGroup(name: String) async throws -> GroupSummary { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func group(id: Int) async throws -> GroupDetail { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func transferGroupAdmin(id: Int, userId: Int) async throws { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func groupProgress(id: Int) async throws -> [GroupProgressMember] { fatalError("fixture-backed GroupPageViewModel must not call the network") }
    func schoolStanding() async throws -> SchoolStanding { fatalError("fixture-backed GroupPageViewModel must not call the network") }
}
#endif
