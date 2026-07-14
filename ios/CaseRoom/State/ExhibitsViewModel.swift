/*
 * Purpose: Drives the candidate's exhibit strip — pre-fetches the exhibit
 *          manifest and each ciphertext blob locked, then decrypts and
 *          reveals an exhibit when its key arrives over the signaling WS.
 * Inputs: sessionId; SessionService (default APIClient.shared). Reveal keys
 *         are fed in via handleReveal(exhibitId:keyB64:) — this VM does not
 *         own the WebSocket subscription; the host view/screen forwards
 *         inbound .reveal SignalMessages to it.
 * Outputs: none (in-memory state only).
 * Run: instantiated by CandidateLiveView; call load() from .task.
 */

import Foundation
import Observation

enum ExhibitDisplayState: Equatable {
    case locked
    case revealed(Data)
}

@Observable
@MainActor
final class ExhibitsViewModel {
    let sessionId: Int

    var exhibits: [ExhibitMeta] = []
    var isLoading = false
    var errorMessage: String?

    private let service: SessionService
    private var ciphertexts: [Int: Data] = [:]
    private var states: [Int: ExhibitDisplayState] = [:]

    init(sessionId: Int, service: SessionService) {
        self.sessionId = sessionId
        self.service = service
    }

    /// This exhibit's current display state — locked until revealed.
    func state(for exhibitId: Int) -> ExhibitDisplayState {
        states[exhibitId] ?? .locked
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let manifest = try await service.exhibits(id: sessionId)
            for meta in manifest {
                let blob = try await service.exhibitBlob(id: sessionId, exhibitId: meta.exhibitId)
                ciphertexts[meta.exhibitId] = blob
                states[meta.exhibitId] = .locked
            }
            exhibits = manifest
        } catch {
            errorMessage = "Couldn't load exhibits. Try again."
        }
    }

    // MARK: - Reveal

    /// Decrypts and reveals the given exhibit. A no-op (no crash, no state
    /// change) if the exhibit id is unknown or decryption fails.
    func handleReveal(exhibitId: Int, keyB64: String) {
        guard let meta = exhibits.first(where: { $0.exhibitId == exhibitId }),
              let ciphertext = ciphertexts[exhibitId] else {
            return
        }
        do {
            let plaintext = try ExhibitCrypto.decrypt(ciphertext: ciphertext, keyB64: keyB64, ivB64: meta.ivB64)
            states[exhibitId] = .revealed(plaintext)
        } catch {
            // Bad key/tag mismatch — leave the exhibit locked rather than crash.
        }
    }
}
