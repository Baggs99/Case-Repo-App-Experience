/*
 * Purpose: Drives the "Get cased now" glass sheet (canvas 3b `sheetNow3`) —
 *          mints a case-less (or T4-prefilled) pairing code + short code for
 *          the QR/copy-link, loads the free-right-now board, and fires
 *          now-invite "pings". Injectable GetCasedService + clipboard writer
 *          so tests never touch the network or the system pasteboard.
 * Inputs: GetCasedService (default APIClient.shared); optional prefillCaseId
 *         (nil = case-less, the default; T4 passes a concrete case); a `now`
 *         clock and a fixture `schools` map (availability carries no school);
 *         a clipboard-writer closure.
 * Outputs: none (in-memory state only).
 * Run: GetCasedNowSheet(viewModel:) presents it; call load() from .task.
 */

import Foundation
import Observation
import UIKit

// The slice of the API the Get-cased-now sheet needs. APIClient conforms
// trivially — `pairCreate(caseId:)`, `availability()`, and `createNowInvite`
// all live on the actor (see APIClient.swift).
protocol GetCasedService {
    func pairCreate(caseId: Int?) async throws -> PairToken
    func availability() async throws -> AvailabilityStatus
    func createNowInvite(toUserId: Int) async throws
}

extension APIClient: GetCasedService {}

@Observable
@MainActor
final class GetCasedNowViewModel {
    /// A free-right-now board row. `school` is fixture-only continuity — the
    /// availability payload (FreeUser) carries no school field, so live rows
    /// omit the "· school" segment gracefully.
    struct LiveNowRow: Identifiable, Equatable {
        let id: Int
        let name: String
        let school: String?
        let minutesFree: Int
    }

    var shortCode: String = ""
    var expiresAt: Date?
    var others: [FreeUser] = []
    var toastMessage: String?
    var errorMessage: String?

    /// The PINNED deep-link payload the QR encodes and Copy-link copies.
    var pairURL: String { "caseroom://pair?code=\(shortCode)" }

    /// Board rows, derived from `others` + the current clock + the fixture
    /// school map. Empty until load() populates `others`.
    var liveNow: [LiveNowRow] {
        others.map { user in
            LiveNowRow(
                id: user.userId,
                name: user.name,
                school: schools[user.userId],
                minutesFree: Self.minutesFree(until: user.freeUntil, from: now())
            )
        }
    }

    private let service: GetCasedService
    private let prefillCaseId: Int?
    private let now: () -> Date
    private let schools: [Int: String]
    private let writeClipboard: (String) -> Void

    init(
        prefillCaseId: Int? = nil,
        service: GetCasedService = APIClient.shared,
        now: @escaping () -> Date = { Date() },
        schools: [Int: String] = [:],
        writeClipboard: @escaping (String) -> Void = { UIPasteboard.general.string = $0 }
    ) {
        self.prefillCaseId = prefillCaseId
        self.service = service
        self.now = now
        self.schools = schools
        self.writeClipboard = writeClipboard
    }

    /// Mints the pairing code (case-less by default) and loads the board. A
    /// single failure surfaces one undesigned error line — the sheet keeps its
    /// Cancel affordance either way.
    func load() async {
        errorMessage = nil
        do {
            let token = try await service.pairCreate(caseId: prefillCaseId)
            shortCode = token.shortCode
            expiresAt = token.expiresAt
            others = try await service.availability().others
        } catch {
            errorMessage = "Couldn't set up a pairing code. Try again."
        }
    }

    /// Whole minutes of availability remaining, clamped at 0 (never negative).
    static func minutesFree(until freeUntil: Date, from now: Date) -> Int {
        max(0, Int((freeUntil.timeIntervalSince(now) / 60).rounded()))
    }

    /// "Ping" a free classmate — a now-invite. Toasts the 2-hour expiry per
    /// the canvas microcopy.
    func ping(userId: Int) async {
        do {
            try await service.createNowInvite(toUserId: userId)
            toastMessage = "expires in 2 h"
        } catch {
            errorMessage = "Couldn't send the invite. Try again."
        }
    }

    /// Copy the pairing deep link for the "Anyone — send a link" row.
    func copyLink() {
        writeClipboard(pairURL)
        toastMessage = "Link copied"
    }
}

#if DEBUG
extension GetCasedNowViewModel {
    /// Fixture VM for `-CaseFixtures` screenshots/Previews (canvas `sheetNow3`):
    /// short code K7Q-4TN, S. Park · Wharton · 45 min free, J. Okafor · INSEAD
    /// · 20 min free. No network — the stub service returns canned data.
    static func fixture() -> GetCasedNowViewModel {
        GetCasedNowViewModel(
            service: FixtureGetCasedService(),
            schools: [501: "Wharton", 502: "INSEAD"]
        )
    }
}

/// Stub GetCasedService seeded with the canvas persona — no network; ping is a
/// canned success so the screenshot hatch never hits a live server.
final class FixtureGetCasedService: GetCasedService {
    func pairCreate(caseId: Int?) async throws -> PairToken {
        PairToken(token: "fixture-token", expiresAt: Date().addingTimeInterval(600), shortCode: "K7Q-4TN")
    }

    func availability() async throws -> AvailabilityStatus {
        AvailabilityStatus(freeUntil: nil, others: [
            FreeUser(userId: 501, name: "S. Park", freeUntil: Date().addingTimeInterval(45 * 60)),
            FreeUser(userId: 502, name: "J. Okafor", freeUntil: Date().addingTimeInterval(20 * 60)),
        ])
    }

    func createNowInvite(toUserId: Int) async throws {}
}
#endif
