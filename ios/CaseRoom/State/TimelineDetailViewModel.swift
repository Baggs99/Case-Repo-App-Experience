/*
 * Purpose: Backing state for the Timeline-detail screen (canvas 7b) — loads the
 *          B7 timeline + firm catalog, derives the headline/readiness rows/add-a
 *          -firm chips, and drives the passed-deadline interview-outcome prompt
 *          state machine (Yes/No -> Offer/No offer/Waiting -> result card).
 * Inputs: TimelineService (default APIClient.shared).
 * Outputs: POST /api/v1/timeline/firms (track), POST .../result (outcome).
 * Run: owned by TimelineDetailView.
 */

import Foundation
import Observation

@Observable
@MainActor
final class TimelineDetailViewModel {
    /// The passed-deadline prompt's state machine. `.result` carries the raw
    /// server response so the view can key its card style off `result.outcome`.
    enum PromptStage: Equatable {
        case initial
        case interviewed
        case result(FirmResult)
    }

    private(set) var detail: TimelineDetail?
    private(set) var catalog: [FirmCatalogEntry] = []
    private(set) var addedFirmIds: Set<Int> = []
    private(set) var promptStage: PromptStage = .initial
    var errorMessage: String?

    private let service: TimelineService
    private let isFixtureBacked: Bool

    init(service: TimelineService = APIClient.shared) {
        self.service = service
        self.isFixtureBacked = false
    }

    #if DEBUG
    /// Screenshot-only: injects fixture data (and, optionally, a pre-set prompt
    /// stage for the -F2TimelinePromptNoOffer hatch) instead of hitting the
    /// network. `load()` is a deliberate no-op on this instance — regardless of
    /// whether a dev server happens to be reachable, the fixture must never be
    /// silently overwritten by a live response.
    init(fixtureDetail: TimelineDetail, fixtureCatalog: [FirmCatalogEntry],
         promptStage: PromptStage = .initial) {
        self.service = NeverCalledTimelineService()
        self.isFixtureBacked = true
        self.detail = fixtureDetail
        self.catalog = fixtureCatalog
        self.promptStage = promptStage
    }
    #endif

    func load() async {
        guard !isFixtureBacked else { return }
        do {
            async let d = service.timeline()
            async let c = service.timelineFirms()
            detail = try await d
            catalog = try await c
        } catch {
            errorMessage = "Couldn't load your timeline."
        }
    }

    // MARK: - Derived data

    /// Non-passed firms carrying a real deadline — the SteppedTimeline and the
    /// per-firm readiness rows both source from this. Freshly-tracked firms with
    /// no deadline yet are `addedRows`, not this.
    var readinessFirms: [TimelineFirmDetail] {
        (detail?.firms ?? []).filter { $0.deadline != nil && $0.deadline?.passed != true }
    }

    var timelineFirms: [TimelineFirm] {
        readinessFirms.compactMap { firm in
            guard let deadline = firm.deadline else { return nil }
            return TimelineFirm(
                name: firm.name,
                date: Self.formattedDate(deadline.deadlineDate),
                days: "\(deadline.daysRemaining)d",
                readiness: Self.tagLabel(firm.readinessTag),
                onPace: firm.readinessTag == "on_track"
            )
        }
    }

    private var soonestFirm: TimelineFirmDetail? {
        readinessFirms.min { ($0.deadline?.daysRemaining ?? .max) < ($1.deadline?.daysRemaining ?? .max) }
    }

    private var soonestDaysRemaining: Int { soonestFirm?.deadline?.daysRemaining ?? 0 }

    /// e.g. "Fifty-eight days." — sentence-leading, so the capitalized spellOut
    /// form is used as-is.
    var headlineDays: String {
        guard let days = soonestFirm?.deadline?.daysRemaining else { return "" }
        return "\(Self.spellOut(days)) days."
    }

    var nextRiserName: String { soonestFirm?.name ?? "" }

    var addableChips: [FirmCatalogEntry] {
        catalog.filter { !$0.tracked && !addedFirmIds.contains($0.firmId) }
    }

    /// Firms tracked this session with no deadline yet — rendered as "Set date" rows.
    var addedRows: [FirmCatalogEntry] {
        catalog.filter { addedFirmIds.contains($0.firmId) }
    }

    /// First firm past its deadline whose prompt is still owed.
    var passedPrompt: TimelineFirmDetail? {
        detail?.firms.first { $0.deadline?.passed == true && $0.prompt.show }
    }

    // MARK: - Row copy (deviation #3: persona sub-prose isn't in the API; a
    // tag-derived line stands in on live screens).

    func secondaryLine(for firm: TimelineFirmDetail) -> String {
        if firm.readinessTag == "focus", let focus = detail?.readiness.focusDimension {
            return "Focus: \(focus)"
        }
        return "\(firm.deadline?.daysRemaining ?? 0) days out"
    }

    func passedHeader(_ firm: TimelineFirmDetail) -> String {
        "PASSED — \(firm.name) · \(Self.formattedDate(firm.deadline?.deadlineDate ?? ""))".uppercased()
    }

    func daysAgo(_ firm: TimelineFirmDetail) -> Int {
        abs(min(firm.deadline?.daysRemaining ?? 0, 0))
    }

    // MARK: - Result-card copy (mid-sentence numbers are lowercased; sentence-
    // leading ones keep spellOut's capitalized first letter).

    func noOfferBody(_ reweight: Reweight) -> String {
        "Noted, not dwelt on. The plan reweights tonight: \(Self.drillPhrase(reweight.suggestedDrillType))" +
        " and \(Self.spellOut(reweight.extraCases.count).lowercased()) extra cases before \(nextRiserName)."
    }

    func noOfferKicker(_ reweight: Reweight) -> String {
        guard let focus = reweight.focusDimension else { return "DIAGNOSTIC UPDATED" }
        return "DIAGNOSTIC UPDATED · FOCUS UNCHANGED: \(focus.uppercased())"
    }

    var droppedBody: String {
        "Off the line it goes. Focus shifts fully to \(nextRiserName) — \(Self.spellOut(soonestDaysRemaining).lowercased()) days."
    }

    // MARK: - Actions

    /// Track a catalog firm and optimistically show it as an added "Set date" row.
    func addFirm(_ firmId: Int) async {
        guard catalog.contains(where: { $0.firmId == firmId }) else { return }
        do {
            try await service.trackFirm(firmId: firmId)
            addedFirmIds.insert(firmId)
        } catch {
            errorMessage = "Couldn't add that firm."
        }
    }

    func answerInterviewed(_ did: Bool) async {
        guard let firm = passedPrompt else { return }
        guard did else {
            do {
                let result = try await service.firmResult(firmId: firm.firmId, outcome: "didnt_interview")
                promptStage = .result(result)
            } catch {
                errorMessage = "Couldn't record that."
            }
            return
        }
        promptStage = .interviewed
    }

    /// outcome is "offer" | "no_offer" | "waiting".
    func recordOutcome(_ outcome: String) async {
        guard let firm = passedPrompt else { return }
        do {
            let result = try await service.firmResult(firmId: firm.firmId, outcome: outcome)
            promptStage = .result(result)
        } catch {
            errorMessage = "Couldn't record that."
        }
    }

    // MARK: - Pure helpers (static so tests can call them directly)

    /// 0–99 spelled out, first letter capitalized ("Fifty-eight"); >=100 falls
    /// back to digits.
    static func spellOut(_ n: Int) -> String {
        guard n >= 0, n < 100 else { return "\(n)" }
        let ones = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                    "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
                    "Eighteen", "Nineteen"]
        if n < 20 { return ones[n] }
        let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
        let ten = n / 10, rem = n % 10
        return rem == 0 ? tens[ten] : "\(tens[ten])-\(ones[rem].lowercased())"
    }

    static func tagLabel(_ tag: String) -> String {
        switch tag {
        case "on_track": return "ON PACE"
        case "focus": return "PUSH QUANT"
        case "early": return "EARLY"
        default: return tag.uppercased()
        }
    }

    static func drillPhrase(_ type: String) -> String {
        switch type {
        case "market_sizing": return "market-sizing drills daily"
        case "mental_math": return "quant drills daily"
        case "framework_recall": return "framework drills daily"
        default: return "drills daily"
        }
    }

    private static let isoDateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "MMM d"
        return f
    }()

    static func formattedDate(_ iso: String) -> String {
        guard let date = isoDateParser.date(from: iso) else { return iso }
        return monthDayFormatter.string(from: date)
    }
}

#if DEBUG
/// Backs the fixture-init VM. The screenshot hatches are documented non-
/// interactive (simctl can't tap/type), so any call here is a misuse — fail
/// loudly instead of silently hitting the network or returning fake writes.
private struct NeverCalledTimelineService: TimelineService {
    func timeline() async throws -> TimelineDetail { fatalError("fixture-backed TimelineDetailViewModel must not call the network") }
    func timelineFirms() async throws -> [FirmCatalogEntry] { fatalError("fixture-backed TimelineDetailViewModel must not call the network") }
    func trackFirm(firmId: Int) async throws { fatalError("fixture-backed TimelineDetailViewModel must not call the network") }
    func untrackFirm(firmId: Int) async throws { fatalError("fixture-backed TimelineDetailViewModel must not call the network") }
    func firmResult(firmId: Int, outcome: String) async throws -> FirmResult { fatalError("fixture-backed TimelineDetailViewModel must not call the network") }
}
#endif
