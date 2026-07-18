/*
 * Purpose: The gauntlet run → submit → percentile-result state machine (canvas
 *          5b run + result). Loads today's server gauntlet (or accepts an
 *          injected one), iterates the 6 slots collecting a signed keypad value
 *          (numeric slots) or a choiceIndex (choice slots) plus a per-slot
 *          durationMs, then POSTs the answers for server re-scoring. B8 allows
 *          one submission/user/day; a 409 is recovered by re-fetching the
 *          embedded result. "See today's result" injects that result to open
 *          straight into the result phase (no re-run).
 *
 *   TIMER JUDGMENT: elapsed is always computed from a wall-clock `Date` (runStart
 *   for the total, slotStart for the per-slot durationMs). A single repeating 1s
 *   tick ONLY refreshes the MM:SS label — it never accumulates, so a dropped or
 *   coalesced tick can't make the clock drift. The tick is invalidated + re-armed
 *   per slot and torn down on submit/stop, so no timer ever leaks across slots.
 *   The `now` clock is injectable so tests are deterministic (no runloop timer).
 *
 *   FM SEAM: this is the SERVER-scored path (submitGauntlet). It never touches
 *   the on-device FM engine — the weak-section CTA bridges to `.drillRun` (the
 *   legacy FM DrillView), which is the only FM-adjacent seam here.
 * Inputs: a GauntletService (default APIClient.shared); optional preloaded
 *         Gauntlet / GauntletResult; injectable `now` clock + `autoTick`.
 * Outputs: one POST /gauntlet/attempts (live run only); no other side effects.
 * Run: owned by RootShell's `.gauntletRun` fullScreenCover; call `start()` on task.
 */

import Foundation
import Observation

@Observable
@MainActor
final class GauntletRunViewModel: Identifiable {
    enum Phase: Equatable {
        case loading
        case running
        case submitting
        case result(GauntletResult)
        case failed(String)
    }

    let id = UUID()
    private(set) var phase: Phase = .loading
    private(set) var currentIndex = 0

    // Numeric-slot keypad state (reset per slot); the choice-slot selection.
    var numericInput = ""
    var isNegative = false
    private(set) var selectedChoice: Int?

    // The collected answers, exposed for tests (one subset-encoded row per slot).
    private(set) var answers: [GauntletAttempt] = []

    // The live MM:SS run clock label (refreshed by the tick; value from `now`).
    private(set) var timerLabel = "00:00"

    private var gauntlet: Gauntlet?
    private var runStart: Date?
    private var slotStart: Date?
    private var ticker: Timer?
    private var resultElapsedSeconds: Int?

    private let service: GauntletService
    private let preloaded: Gauntlet?
    private let preloadedResult: GauntletResult?
    private let now: () -> Date
    private let autoTick: Bool

    init(service: GauntletService = APIClient.shared,
         preloaded: Gauntlet? = nil,
         preloadedResult: GauntletResult? = nil,
         preloadedElapsedSeconds: Int? = nil,
         now: @escaping () -> Date = { Date() },
         autoTick: Bool = true) {
        self.service = service
        self.preloaded = preloaded
        self.preloadedResult = preloadedResult
        self.resultElapsedSeconds = preloadedElapsedSeconds
        self.now = now
        self.autoTick = autoTick
    }

    // MARK: - Lifecycle

    /// Entry point (idempotent-ish: only acts from `.loading`). Opens straight
    /// into `.result` when a preloaded result is supplied ("See today's
    /// result"); otherwise starts the timed run from the injected or fetched
    /// gauntlet, defensively showing an already-scored result if the server
    /// says today is already submitted.
    func start() async {
        guard case .loading = phase else { return }
        if let result = preloadedResult {
            phase = .result(result)
            return
        }
        if let gauntlet = preloaded {
            beginRun(with: gauntlet)
            return
        }
        do {
            let gauntlet = try await service.gauntlet()
            if gauntlet.submitted, let result = gauntlet.result {
                phase = .result(result)
            } else {
                beginRun(with: gauntlet)
            }
        } catch {
            phase = .failed("Couldn't load today's gauntlet. Try again.")
        }
    }

    private func beginRun(with gauntlet: Gauntlet) {
        self.gauntlet = gauntlet
        answers = []
        currentIndex = 0
        resetSlotInput()
        let start = now()
        runStart = start
        slotStart = start
        phase = .running
        refreshTimer()
        armTicker()
    }

    /// Abandon: stop the clock, submit nothing (streak survives). The view
    /// dismisses the cover.
    func stop() { invalidateTicker() }

    // MARK: - Slots

    var slots: [GauntletSlot] { gauntlet?.slots ?? [] }
    var currentSlot: GauntletSlot? { slots.indices.contains(currentIndex) ? slots[currentIndex] : nil }
    var isNumericSlot: Bool { currentSlot?.choices == nil }

    /// Numeric-slot Next is gated on a parseable value; choice slots advance on tap.
    var canAdvance: Bool { GauntletKeypad.signedValue(input: numericInput, isNegative: isNegative) != nil }

    private func resetSlotInput() {
        numericInput = ""
        isNegative = false
        selectedChoice = nil
    }

    /// Numeric-slot advance (keypad "Next"): captures the signed value.
    func advance() async {
        guard case .running = phase, let slot = currentSlot, slot.choices == nil else { return }
        let value = GauntletKeypad.signedValue(input: numericInput, isNegative: isNegative)
        record(GauntletAttempt(slot: slot.slot, value: value, choiceIndex: nil, durationMs: durationMsForSlot()))
        await advanceOrSubmit()
    }

    /// Choice-slot tap: records the choiceIndex and advances.
    func selectChoice(_ index: Int) async {
        guard case .running = phase, let slot = currentSlot, slot.choices != nil else { return }
        selectedChoice = index
        record(GauntletAttempt(slot: slot.slot, value: nil, choiceIndex: index, durationMs: durationMsForSlot()))
        await advanceOrSubmit()
    }

    private func record(_ attempt: GauntletAttempt) { answers.append(attempt) }

    private func advanceOrSubmit() async {
        if currentIndex + 1 < slots.count {
            currentIndex += 1
            resetSlotInput()
            slotStart = now()
            armTicker()               // invalidate + re-arm: never a leaked tick across slots
        } else {
            await submit()
        }
    }

    private func durationMsForSlot() -> Int {
        guard let start = slotStart else { return 0 }
        return max(0, Int(now().timeIntervalSince(start) * 1000))
    }

    // MARK: - Submit + recovery

    private func submit() async {
        invalidateTicker()
        if let start = runStart { resultElapsedSeconds = Int(now().timeIntervalSince(start)) }
        phase = .submitting
        do {
            let result = try await service.submitGauntlet(answers)
            phase = .result(result)
        } catch GauntletError.alreadySubmitted {
            await recoverAlreadySubmitted()
        } catch {
            phase = .failed("Couldn't score your gauntlet. Try again.")
        }
    }

    /// 409 recovery: re-fetch the gauntlet and show its embedded (already-scored)
    /// result — the one-per-day submission already happened.
    private func recoverAlreadySubmitted() async {
        do {
            let gauntlet = try await service.gauntlet()
            if let result = gauntlet.result {
                phase = .result(result)
            } else {
                phase = .failed("You already ran today's gauntlet.")
            }
        } catch {
            phase = .failed("Couldn't load your result. Try again.")
        }
    }

    // MARK: - Timer (wall-clock derived; the tick only refreshes the label)

    private func armTicker() {
        guard autoTick else { return }
        ticker?.invalidate()
        // Weak self + self-invalidation: if the VM is gone, the tick invalidates
        // its own Timer (no leaked runloop tick, no nonisolated-deinit access).
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in self.refreshTimer() }
        }
    }

    private func invalidateTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func refreshTimer() {
        guard let start = runStart else { return }
        timerLabel = Self.mmss(Int(now().timeIntervalSince(start)))
    }

    // MARK: - Run labels

    var kicker: String {
        guard let slot = currentSlot else { return "" }
        return "\(Self.typeLabel(slot.drillType)) — \(currentIndex + 1) OF \(slots.count)"
    }

    var progress: Double {
        guard !slots.isEmpty else { return 0 }
        return Double(currentIndex) / Double(slots.count)
    }

    /// The client drillType→label map (the server's GAUNTLET_TYPE_LABELS isn't on
    /// the wire); an unmapped type falls back to CAPS with underscores spaced.
    static func typeLabel(_ drillType: String) -> String {
        switch drillType {
        case "mental_math": return "MENTAL MATH"
        case "market_sizing": return "MARKET SIZING"
        case "framework_recall": return "STRUCTURES"
        default: return drillType.uppercased().replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: - Result labels

    private var resultValue: GauntletResult? {
        if case let .result(result) = phase { return result }
        return nil
    }

    /// Split for the big-number + small-suffix render (72px / 28px). A nil
    /// percentile (cold start / pre-rank) renders a graceful "—" with no suffix.
    var resultPercentileNumber: String {
        guard let pct = resultValue?.dailyPercentile else { return "—" }
        return String(Int(pct.rounded()))
    }

    var resultPercentileSuffix: String {
        guard let pct = resultValue?.dailyPercentile else { return "" }
        return String(Self.ordinal(Int(pct.rounded())).suffix(2))
    }

    /// Combined ordinal ("66TH") or the graceful "—" — the VM-level string the
    /// tests assert never crashes on a nil percentile.
    var resultPercentileLabel: String {
        guard let pct = resultValue?.dailyPercentile else { return "—" }
        return Self.ordinal(Int(pct.rounded()))
    }

    var resultKicker: String {
        if let seconds = resultElapsedSeconds {
            return "PERCENTILE · TODAY'S GAUNTLET · \(Self.mmss(seconds))"
        }
        return "PERCENTILE · TODAY'S GAUNTLET"
    }

    var resultPointsLabel: String { "+\(resultValue?.pointsAwarded ?? 0) PTS" }

    var resultCorrectLabel: String {
        guard let result = resultValue else { return "" }
        return "\(result.slotsCorrect)/\(result.slots) CORRECT"
    }

    /// "{ordinal(rank)} IN {group} TODAY" — only when the result carries a group
    /// (nil hides the strip segment; no fiction).
    var resultGroupLabel: String? {
        guard let group = resultValue?.group else { return nil }
        let name = group.name ?? "your cohort"
        return "\(Self.ordinal(group.rank)) IN \(name) TODAY"
    }

    /// Derived serif line (mobile-DC JS logic is truncated in the canvas tail —
    /// this is composed from the weakSection per persona §3; owner-gate at demo).
    var resultSerifLine: String {
        if let weak = resultValue?.weakSection {
            return "Your \(weak.label) came in soft today — a few focused reps sharpen it fast."
        }
        return "Solid run today. Come back tomorrow and keep the streak climbing."
    }

    /// The FM practice bridge label: the weak section, else a generic weak spot.
    var weakCtaLabel: String {
        if let weak = resultValue?.weakSection {
            return "Practice \(weak.label) — 3 focused drills"
        }
        return "Practice a weak spot — 3 focused drills"
    }

    // MARK: - Formatting helpers

    static func mmss(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        let suffix: String
        if (11...13).contains(mod100) {
            suffix = "TH"
        } else {
            switch n % 10 {
            case 1: suffix = "ST"
            case 2: suffix = "ND"
            case 3: suffix = "RD"
            default: suffix = "TH"
            }
        }
        return "\(n)\(suffix)"
    }
}
