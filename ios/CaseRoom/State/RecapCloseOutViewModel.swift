/*
 * Purpose: The recap CLOSE-OUT sheet's logic (F5 Task 7, canvas 6b close-out) —
 *          the GATE mechanism that floats over the T6 recap report. The pure
 *          rules (scroll progress, the bottom − 16 unlock threshold, the % label,
 *          the required-rating gate) live in RecapCloseOutPresentation so they
 *          unit-test without a view; RecapCloseOutViewModel drives the required
 *          1–5 rating, the optional thumbs, and the `recapClose` call that clears
 *          the candidate's recap gate.
 * Inputs: sessionId; a SessionFlowService (APIClient live; a fixture stub under
 *         the -startRecap shot hatch). Scroll metrics are fed in by the report view.
 * Outputs: RecapCloseOutPresentation (pure), RecapCloseOutViewModel (@Observable).
 * Run: owned by RecapReportView, mounted in its T7 overlay seam; Close →
 *      recapClose → "Gate cleared." toast → dismiss the recap cover.
 */

import Foundation
import Observation

// MARK: - Pure rules (the genuinely testable bits)

enum RecapCloseOutPresentation {
    /// The unlock threshold: the close-out unlocks once the report has scrolled to
    /// within this many points of the bottom (canvas 6b: "unlocks at scrollBottom − 16").
    static let unlockThreshold: CGFloat = 16

    /// Live read-progress (0…1) from the report's scroll offset. `offset` is how
    /// far the report has scrolled DOWN (>= 0); the scrollable distance is the
    /// content height minus the viewport. Clamped; unmeasured (0 sizes) → 0.
    static func scrollProgress(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Double {
        guard contentHeight > 0, viewportHeight > 0 else { return 0 }
        let scrollable = Swift.max(contentHeight - viewportHeight, 0)
        guard scrollable > 0 else { return 1 }   // fits on one screen → nothing to read past
        return Swift.min(Swift.max(Double(offset / scrollable), 0), 1)
    }

    /// Whether the close-out has unlocked: the report has reached bottom − threshold.
    /// Unmeasured sizes (either dimension still 0) read locked so the sheet never
    /// unlocks before the report has laid out. Content shorter than the viewport
    /// (scrollable <= 0) unlocks immediately — there is nothing left to read.
    static func isUnlocked(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat,
                           threshold: CGFloat = unlockThreshold) -> Bool {
        guard contentHeight > 0, viewportHeight > 0 else { return false }
        let scrollable = Swift.max(contentHeight - viewportHeight, 0)
        return offset >= scrollable - threshold
    }

    /// The locked line's "N%" — whole-percent, clamped, tabular at the call site.
    static func percentLabel(_ progress: Double) -> String {
        let pct = Int((Swift.min(Swift.max(progress, 0), 1) * 100).rounded())
        return "\(pct)%"
    }

    /// The 1–5 rating gate: only a value in 1…5 is a valid close-out rating (the
    /// server 422s otherwise). Close is DISABLED until a valid rating is chosen.
    static func isValidRating(_ n: Int) -> Bool { (1...5).contains(n) }
}

// MARK: - Close-out view model

@Observable
@MainActor
final class RecapCloseOutViewModel {
    let sessionId: Int
    private let flow: SessionFlowService

    /// The candidate's chosen 1–5 rating (0 = unrated → Close disabled).
    var rating = 0
    /// Optional feedback-quality thumbs: nil = none, true = "Worth it", false =
    /// "Thin". Always sent; the backend records it only for a non-guest
    /// interviewer (the client need not know guest-ness).
    var thumbs: Bool?
    /// True while a `recapClose` is in flight (guards double-taps).
    var closing = false
    /// True once the gate is cleared (success OR a 409 re-close).
    var cleared = false
    /// The "Gate cleared." toast text, bound to `.dsToast`.
    var toast: String?
    var closeError: String?

    init(sessionId: Int, flow: SessionFlowService) {
        self.sessionId = sessionId
        self.flow = flow
    }

    /// Close is disabled until a valid 1–5 is chosen (the required close endpoint).
    var canClose: Bool { RecapCloseOutPresentation.isValidRating(rating) }

    /// Pick the required 1–5 case rating (a 0 / out-of-range tap is ignored).
    func pick(_ n: Int) {
        guard RecapCloseOutPresentation.isValidRating(n) else { return }
        closeError = nil
        rating = n
    }

    /// Toggle a thumb; re-tapping the chosen side clears it back to "none".
    func toggleThumb(_ value: Bool) {
        thumbs = (thumbs == value) ? nil : value
    }

    /// Close the recap: the REQUIRED 1–5 rating clears the gate. On success (or a
    /// 409 re-close, which means it was already closed) → "Gate cleared." toast,
    /// then dismiss the recap cover via `onCleared`. A 422 (missing/out-of-range
    /// rating) shouldn't happen — the button gates on a valid rating — but is
    /// handled defensively by rolling back to a re-tappable state.
    func close(onCleared: @escaping @MainActor () -> Void) async {
        guard canClose, !closing, !cleared else { return }
        closing = true
        closeError = nil
        defer { closing = false }
        do {
            _ = try await flow.recapClose(id: sessionId, caseRating: rating, thumbs: thumbs)
            await clearGate(onCleared)
        } catch APIError.server(409) {
            // Re-close: the recap is already closed → the gate is already clear.
            await clearGate(onCleared)
        } catch APIError.server(422) {
            rating = 0
            closeError = "Pick a 1–5 rating to close out."
        } catch {
            closeError = "Couldn't close out. Try again."
        }
    }

    private func clearGate(_ onCleared: @escaping @MainActor () -> Void) async {
        cleared = true
        toast = "Gate cleared."
        // Let the toast land before the recap cover drops (the candidate seat
        // reopens; the recap simply leaves the unread list — no client mutation).
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        onCleared()
    }
}
