/*
 * Purpose: Drives QR pairing (Task 14) — interviewer flow mints a token,
 *          renders it as a QR, and polls until the candidate's claim
 *          creates the session; candidate flow claims a scanned token and
 *          surfaces the created session id. Injectable PairService so
 *          tests never touch the network.
 * Inputs: PairService (default APIClient.shared); pollInterval (default
 *         2s; tests inject a near-zero interval to run fast).
 * Outputs: none (in-memory state only).
 * Run: instantiated by PairCreateView / PairScanView; call create(caseId:)
 *      or claim(token:) from .task/button actions.
 */

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class PairViewModel {
    // Interviewer flow
    var token: String?
    var expiresAt: Date?
    var qrImage: UIImage?
    var readySessionId: Int?

    // Candidate flow
    var claimedSessionId: Int?

    var isLoading = false
    var errorMessage: String?

    private let service: PairService
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    init(service: PairService = APIClient.shared, pollInterval: Duration = .seconds(2)) {
        self.service = service
        self.pollInterval = pollInterval
    }

    // MARK: - Interviewer

    /// Mints a pairing token for the chosen case, renders it as a QR, and
    /// starts polling for the session the candidate's claim will create.
    func create(caseId: Int) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let pair = try await service.pairCreate(caseId: caseId)
            token = pair.token
            expiresAt = pair.expiresAt
            qrImage = QRCode.image(from: pair.token)
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                await self?.pollUntilReady()
            }
        } catch {
            errorMessage = "Couldn't create a pairing code. Try again."
        }
    }

    /// Polls pairStatus(token:) until it returns a claimed session id.
    /// Exposed directly (rather than only via create()'s background Task)
    /// so tests can await it deterministically.
    func pollUntilReady() async {
        guard let token else { return }
        while !Task.isCancelled {
            do {
                if let sessionId = try await service.pairStatus(token: token) {
                    readySessionId = sessionId
                    return
                }
            } catch {
                // Transient network error — keep polling rather than
                // stranding the interviewer on a dead screen.
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Candidate

    /// Claims a scanned token, creating the session with this user as
    /// candidate, and stores the resulting session id.
    func claim(token: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            claimedSessionId = try await service.pairClaim(token: token)
        } catch {
            errorMessage = "Couldn't join this session. Try again."
        }
    }
}
