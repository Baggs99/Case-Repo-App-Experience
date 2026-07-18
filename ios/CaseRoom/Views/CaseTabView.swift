/*
 * Purpose: Case tab — canvas 3b "calm spine" (CANON, phone). A slim glass verb
 *          bar (glass CHROME, ONE filled button: "Get cased now") plus the
 *          recap-gate card — the screen's ONE glass HERO (canvas 3b line 1544
 *          is glass; filled "Read the recap" is the 2nd sanctioned filled
 *          exception) — then flat hairline sections: NEXT UP (leading green
 *          blink dot on the imminent session + Swap + tabular countdown),
 *          UPCOMING (hollow-ring dot, rise-in, tabular countdown,
 *          add-to-calendar), PENDING (Accept/New time/Decline + hairline
 *          "awaiting reply" sent rows), and HISTORY. Verb-bar taps present
 *          three MARK-bounded placeholder sheets (T3/T4/T5 fill the bodies);
 *          a recap gate (either tapped or a 409-surfaced
 *          `gatedRecapSessionID`) pushes the interim RecapGateStub (F5
 *          replaces at merge) onto casePath.
 * Inputs: CaseTabViewModel (default live). DEBUG `-CaseFixtures` (wired in
 *         RootShell's caseTabRoot, mirrors `-GroupPageFixtures`) injects
 *         CaseFixtures.makeViewModel() — no dev server needed.
 * Outputs: none directly; AppRouter.shared.casePath pushes for `.recap`;
 *          CaseTabViewModel actions (accept/decline/counter/addToCalendar)
 *          as side effects of row taps.
 * Run: mounted by RootShell inside `NavigationStack(path: $router.casePath)`
 *      for DSTab.caseTab.
 */

import SwiftUI

// MARK: - The verb-bar sheet seam (T3/T4/T5 replace CaseSheetPlaceholder's
// body per sheet — the enum + `.sheet(item:)` wiring below is the stable seam).
enum CaseSheet: Identifiable, Hashable {
    case getCased, caseSomeone, schedule

    var id: Self { self }

    var title: String {
        switch self {
        case .getCased: return "Get cased now"
        case .caseSomeone: return "Case someone"
        case .schedule: return "Schedule"
        }
    }
}

// MARK: - Pure section-presence logic (unit-tested; mirrors LibraryDetailCopy).
// Hide a kicker+block entirely when its data is empty — never render an empty
// section header (T2 brief).
struct CaseTabSectionVisibility: Equatable {
    let showsRecapGate: Bool
    let showsNextUp: Bool
    let showsUpcoming: Bool
    let showsPending: Bool
    let showsHistory: Bool

    /// True only when nothing at all renders — the minimal serif empty line.
    var isEmptyState: Bool {
        !showsRecapGate && !showsNextUp && !showsUpcoming && !showsPending && !showsHistory
    }

    static func compute(
        hasGateRecap: Bool, hasNextUp: Bool,
        upcomingCount: Int, pendingReceivedCount: Int, sentAwaitingCount: Int, historyCount: Int
    ) -> CaseTabSectionVisibility {
        CaseTabSectionVisibility(
            showsRecapGate: hasGateRecap,
            showsNextUp: hasNextUp,
            showsUpcoming: upcomingCount > 0,
            showsPending: pendingReceivedCount > 0 || sentAwaitingCount > 0,
            showsHistory: historyCount > 0
        )
    }
}

// MARK: - Pure copy helper (unit-tested) — PENDING row label depends on which
// side of the proposal made the offer (canvas: "T. Becker offers to interview
// you" vs "S. Park asks you to interview").
enum CaseTabCopy {
    static func pendingOfferLabel(fromName: String, fromRole: String) -> String {
        fromRole == "candidate" ? "\(fromName) asks you to interview" : "\(fromName) offers to interview you"
    }

    /// Canvas 3b's right-aligned relative countdown ("T-6H" style, tabular).
    /// nil when there's no scheduled time to count down to.
    static func countdown(to date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "NOW" }
        let hours = seconds / 3600
        if hours < 24 {
            return "T-\(max(1, Int(hours.rounded(.up))))H"
        }
        let days = Int((hours / 24).rounded(.up))
        return "T-\(days)D"
    }
}

// MARK: - Pure gate-navigation helper (unit-tested) — extracted from the
// `.onChange(of: viewModel.gatedRecapSessionID)` handler so the "append +
// clear" steering is testable without rendering the SwiftUI view.
enum CaseTabGateSteering {
    static func steer(sessionID: Int?, casePath: inout [AppRoute], clearGate: () -> Void) {
        guard let sessionID else { return }
        casePath.append(.recap(sessionID))
        clearGate()
    }
}

// MARK: - Pure tablet-vs-phone layout selection (unit-tested; F3 T6) — mirrors
// CasesListView/CommunityView's `hSize == .regular` branch, extracted so the
// selection rule is testable without rendering SwiftUI.
enum CaseTabLayout {
    static func isTablet(_ hSize: UserInterfaceSizeClass?) -> Bool { hSize == .regular }
}

// MARK: - Pure F4→F3 prefill-steering (unit-tested) — maps the router's
// case-prefill state onto which verb-bar sheet to open. The two prefill fields
// are mutually exclusive by construction (a done case → caseSomeone; an open
// case → getCased); caseSomeone is given priority defensively.
enum CasePrefillSteering {
    enum Target: Equatable {
        case getCased(Int)
        case caseSomeone(id: Int, title: String?)
    }

    static func target(getCasedID: Int?, someoneID: Int?, someoneTitle: String?) -> Target? {
        if let someoneID { return .caseSomeone(id: someoneID, title: someoneTitle) }
        if let getCasedID { return .getCased(getCasedID) }
        return nil
    }
}

/// Captured case-someone prefill context (id + optional title), held in view
/// state across the router-field clear so the sheet VM reads it at build time.
struct CaseSomeonePrefillContext: Equatable {
    let id: Int
    let title: String?
}

struct CaseTabView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var router = AppRouter.shared
    @State private var viewModel: CaseTabViewModel
    @State private var activeSheet: CaseSheet?
    @State private var acceptChoiceProposal: Proposal?
    @State private var counterTarget: Proposal?
    @State private var counterDate = Date()
    @State private var toastMessage: String?
    @State private var upcomingAppeared = false
    // F4→F3 prefill: captured before the router fields are cleared (clearing
    // prevents re-trigger) so the sheet VMs still read the case context when
    // `.sheet(item:)` builds them on the next render.
    @State private var getCasedPrefillCaseID: Int?
    @State private var caseSomeonePrefill: CaseSomeonePrefillContext?

    // Injectable VM (default = live). RootShell's `-CaseFixtures` hatch
    // (caseTabRoot) passes CaseFixtures.makeViewModel() — mirrors
    // GroupPageView/AvatarSheetView's `init(viewModel:)` pattern.
    @MainActor
    init(viewModel: CaseTabViewModel = CaseTabViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .task { await viewModel.load() }
            .onAppear {
                presentSheetHatchIfNeeded()
                consumePrefill()   // cold path: field set before this view observed a change
            }
            // F4→F3 seam: the library CTA sets a router prefill field + selects
            // the Case tab; consume it here to open the matching verb-bar sheet
            // with the case pre-filled, then clear so it can't re-trigger.
            .onChange(of: router.caseGetCasedPrefillCaseID) { _, _ in consumePrefill() }
            .onChange(of: router.caseSomeonePrefillCaseID) { _, _ in consumePrefill() }
            // B3 recap gate: any action that 409s with blockedByRecap sets
            // gatedRecapSessionID — steer to the interim recap stub, then
            // clear so a later gate can re-fire (plain Int? never re-fires
            // the same value twice).
            .onChange(of: viewModel.gatedRecapSessionID) { _, newValue in
                CaseTabGateSteering.steer(sessionID: newValue, casePath: &AppRouter.shared.casePath) {
                    viewModel.clearGate()
                }
            }
            .onChange(of: viewModel.calendarError) { _, newValue in
                guard let newValue else { return }
                toastMessage = newValue
                viewModel.calendarError = nil
            }
            .dsToast(item: $toastMessage)
            .confirmationDialog(
                "Choose a time", isPresented: acceptChoiceIsPresented, titleVisibility: .visible
            ) {
                if let proposal = acceptChoiceProposal {
                    ForEach(proposal.proposedTimes, id: \.self) { time in
                        Button(Self.dateTimeFormatter.string(from: time)) {
                            Task { await viewModel.accept(proposal, at: time) }
                        }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .getCased:
                    // T3 — the real Get-cased-now glass sheet (canvas `sheetNow3`).
                    GetCasedNowSheet(viewModel: makeGetCasedViewModel())
                case .caseSomeone:
                    // T4 — the real Case-someone glass sheet (canvas `sheetSomeone3`).
                    CaseSomeoneSheet(viewModel: makeCaseSomeoneViewModel())
                case .schedule:
                    // T5 — the real Schedule-later composer glass sheet (canvas `sheetLater3`).
                    ScheduleComposerSheet(viewModel: makeScheduleViewModel())
                }
            }
            .sheet(item: $counterTarget) { proposal in
                NewTimeSheet(proposal: proposal, date: $counterDate) { chosen in
                    Task { await viewModel.counter(proposal, times: [chosen]) }
                }
            }
    }

    private var acceptChoiceIsPresented: Binding<Bool> {
        Binding(get: { acceptChoiceProposal != nil }, set: { if !$0 { acceptChoiceProposal = nil } })
    }

    /// Consume any F4→F3 router prefill: capture the case context into view
    /// state, open the matching sheet, and clear the router fields so it can't
    /// re-trigger (a plain Int? never re-fires the same value twice).
    @MainActor
    private func consumePrefill() {
        guard let target = CasePrefillSteering.target(
            getCasedID: router.caseGetCasedPrefillCaseID,
            someoneID: router.caseSomeonePrefillCaseID,
            someoneTitle: router.caseSomeonePrefillTitle
        ) else { return }
        switch target {
        case .getCased(let id):
            getCasedPrefillCaseID = id
            activeSheet = .getCased
        case .caseSomeone(let id, let title):
            caseSomeonePrefill = CaseSomeonePrefillContext(id: id, title: title)
            activeSheet = .caseSomeone
        }
        router.caseGetCasedPrefillCaseID = nil
        router.caseSomeonePrefillCaseID = nil
        router.caseSomeonePrefillTitle = nil
    }

    /// Get-cased-now sheet VM: live by default (with any F4 case prefill); the
    /// `-CaseFixtures` screenshot hatch swaps in the canvas-persona stub
    /// (K7Q-4TN, S. Park / J. Okafor) so the sheet renders with no dev server.
    @MainActor
    private func makeGetCasedViewModel() -> GetCasedNowViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CaseFixtures") {
            return .fixture()
        }
        #endif
        return GetCasedNowViewModel(prefillCaseId: getCasedPrefillCaseID)
    }

    /// Case-someone sheet VM: live by default (with any F4 case-someone prefill
    /// context); the `-CaseFixtures` hatch swaps in the canvas-persona stub (S.
    /// Park invite + "2 cased this month · 4.7 avg feedback quality").
    @MainActor
    private func makeCaseSomeoneViewModel() -> CaseSomeoneViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CaseFixtures") {
            return .fixture()
        }
        #endif
        return CaseSomeoneViewModel(
            prefillCaseId: caseSomeonePrefill?.id,
            prefillCaseTitle: caseSomeonePrefill?.title
        )
    }

    /// Schedule-later composer VM: live by default; the `-CaseFixtures`
    /// screenshot hatch swaps in the canvas-persona stub (S. Park / T. Becker /
    /// M. Lindqvist + the EV-charging recommendation, a ready-to-send composer).
    @MainActor
    private func makeScheduleViewModel() -> ScheduleComposerViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CaseFixtures") {
            return .fixture()
        }
        #endif
        return ScheduleComposerViewModel()
    }

    /// DEBUG screenshot hatch: `-CaseSheet getCased` (only under `-CaseFixtures`)
    /// opens the sheet on appear so simctl can capture the OPEN sheet with no
    /// dev server and no tapping. Release-inert.
    private func presentSheetHatchIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-CaseFixtures"),
              let index = args.firstIndex(of: "-CaseSheet"), index + 1 < args.count else { return }
        switch args[index + 1] {
        case "getCased": activeSheet = .getCased
        case "caseSomeone": activeSheet = .caseSomeone
        case "schedule": activeSheet = .schedule
        default: break
        }
        #endif
    }

    // F3 T6: tablet (`.regular`) gets canvas Tablet 1b's tray hero +
    // two-column spine; every other size class keeps the unchanged phone
    // spine below.
    @ViewBuilder
    private var content: some View {
        if CaseTabLayout.isTablet(hSize) {
            caseTabTablet
        } else {
            casePhoneSpine
        }
    }

    private var casePhoneSpine: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                verbBar
                recapGateCard
                nextUpSection
                upcomingSection
                pendingSection
                historySection
                emptyState
                Color.clear.frame(height: 120)   // room behind the tab bar
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .dsHeaderFade()
    }

    // MARK: - Tablet layout (canvas Tablet 1b "tray hero + two-column spine",
    // Decisions §7 T6). REUSES recapGateCard/nextUpSection/upcomingSection/
    // pendingSection/historySection verbatim — new here is only the glass
    // tray hero (verb column + LIVE NOW board) and the two-column grid
    // wrapper. RootShell already draws the centered "Case" H1 + top pills
    // chrome on `.regular` (same "no H1 here" convention as
    // CasesListView/LibraryMasterDetailView), so `header` is intentionally
    // omitted below.

    private var caseTabTablet: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage).padding(.horizontal, 28).padding(.top, 10)
            }
            tabletTrayHero
                // The tray isn't inside a ScrollView, so RootShell's
                // `.contentMargins(.top, 64, for: .scrollContent)` (which
                // clears its floating wordmark/H1/avatar header row for
                // scrollable content) doesn't reach it — match that same
                // 64pt clearance directly so the tray doesn't sit under it.
                .padding(.horizontal, 28).padding(.top, 64)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    emptyState.padding(.horizontal, 28).padding(.top, 18)
                    tabletSpine
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Tray hero (canvas: 32px-radius glass panel, 300px verb column |
    // vertical hairline | inline LIVE-NOW board). The screen's glass hero —
    // recapGateCard below stays glass too (tablet 1b shows both; canvas §5's
    // "one glass hero" rule is a Part-I/phone rule).

    // A bare `Rectangle()` with only `.frame(width:)` has no bounded height,
    // so SwiftUI treats it as vertically flexible — inside an HStack that
    // makes the WHOLE row (and the glassPanel behind it) report as flexible
    // too, and it balloons to fill the tab's entire available height. Pin the
    // divider to the verb column's own fixed height (its tallest sibling —
    // 54pt ink button + 8pt spacing + 42pt glass row = 104) so the row — and
    // the tray card around it — hugs its real content height instead.
    private static let tabletVerbColumnHeight: CGFloat = 54 + 8 + 42

    private var tabletTrayHero: some View {
        HStack(alignment: .center, spacing: 18) {
            tabletVerbColumn
            Rectangle().fill(palette.ink.opacity(0.12)).frame(width: 1, height: Self.tabletVerbColumnHeight)
            tabletLiveNowBoard
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .glassPanel(cornerRadius: 32)
    }

    /// 300pt verb column: filled ink "Get cased now" (h54) + two glass verbs
    /// (h42 each) — "Case someone" / "Schedule later" (verbatim tablet
    /// copy — phone's third verb says "Schedule"). Same three sheets, same
    /// `activeSheet` seam as phone's verbBar.
    private var tabletVerbColumn: some View {
        VStack(spacing: 8) {
            Button { activeSheet = .getCased } label: {
                Text("Get cased now")
                    .font(.archivo(14.5, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .frame(maxWidth: .infinity).frame(height: 54)
            }
            .buttonStyle(DSPressStyle())
            .background(Capsule().fill(palette.ink))

            HStack(spacing: 8) {
                Button { activeSheet = .caseSomeone } label: {
                    Text("Case someone")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(DSPressStyle())
                .glassChipFlat()

                Button { activeSheet = .schedule } label: {
                    Text("Schedule later")
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(DSPressStyle())
                .glassChipFlat()
            }
        }
        .frame(width: 300)
    }

    /// Inline LIVE-NOW board — same free-right-now data (VM's `liveNow`,
    /// F3 T6) as T3's Get-cased-now sheet, surfaced right in the tray so a
    /// "Ping" needs no sheet at all.
    private var tabletLiveNowBoard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIVE NOW — FREE TO CASE YOU")
                    .font(.archivo(9.5, weight: 600)).tracking(0.15 * 9.5)
                    .foregroundStyle(palette.muted)
                Spacer()
                Text("PINGS EXPIRE IN 2 H")
                    .font(.archivo(8.5, weight: 600)).tracking(0.12 * 8.5)
                    .foregroundStyle(palette.faint)
            }
            ForEach(Array(viewModel.liveNow.enumerated()), id: \.element.id) { index, row in
                tabletLiveNowRow(row, isLast: index == viewModel.liveNow.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabletLiveNowRow(_ row: CaseTabViewModel.LiveNowRow, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            (Text("\(row.name) ").font(.archivo(13, weight: 600)).foregroundStyle(palette.ink)
                + Text(Self.liveNowMeta(row)).font(.archivo(11, weight: 400)).foregroundStyle(palette.muted))
            Spacer(minLength: 8)
            Button {
                Task {
                    let ok = await viewModel.ping(userId: row.id)
                    if ok { toastMessage = "Pinged \(row.name) — expires in 2 h" }
                }
            } label: {
                Text("Ping")
                    .font(.archivo(11, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 14).frame(height: 32)
            }
            .buttonStyle(DSPressStyle())
            .background(Capsule().fill(palette.ink))
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(palette.ink.opacity(0.1)).frame(height: 1) }
        }
    }

    private static func liveNowMeta(_ row: CaseTabViewModel.LiveNowRow) -> String {
        let school = row.school.map { "\($0) · " } ?? ""
        return "· \(school)\(row.minutesFree) min free"
    }

    // MARK: - Two-column spine (canvas: `grid 1fr 1fr gap 36`). Left =
    // recap-gate card → NEXT UP → UPCOMING; right = PENDING → HISTORY, both
    // reusing the phone's exact subviews. "Accept crosses columns" (canvas
    // §7-1b): CaseTabViewModel.accept() already moves the proposal from
    // pendingReceived into upcoming/nextUp (see
    // testAcceptRemovesFromPendingReceivedRefreshesUpcomingAndAddsToCalendarOnce);
    // the `.animation(value:)` below gives that state move a tasteful
    // cross-column fade/rise rather than a hard cut — a full matched-geometry
    // cross-column transition proved fiddly against reused, independently-
    // laid-out subviews, so this is the documented "tasteful fade" fallback
    // the brief allows.
    private var tabletSpine: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 16) {
                recapGateCard
                nextUpSection
                upcomingSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                pendingSection
                historySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 110)
        .animation(DSMotion.riseCurve, value: viewModel.pendingReceived)
        .animation(DSMotion.riseCurve, value: viewModel.upcoming)
        .animation(DSMotion.riseCurve, value: viewModel.nextUp)
    }

    private var header: some View {
        Text("Case").dsText(.h1Tab).foregroundStyle(palette.ink)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load() } } label: {
                Text("Retry").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private var visibility: CaseTabSectionVisibility {
        CaseTabSectionVisibility.compute(
            hasGateRecap: viewModel.gateRecap != nil,
            hasNextUp: viewModel.nextUp != nil,
            upcomingCount: viewModel.upcoming.count,
            pendingReceivedCount: viewModel.pendingReceived.count,
            sentAwaitingCount: viewModel.sentAwaiting.count,
            historyCount: viewModel.history.count
        )
    }

    // MARK: - 1. Slim glass verb bar — the ONE glass hero + ONE filled button
    // on this screen (canvas 3b 1537-1541). Filled "Get cased now"; the other
    // two verbs are underline text, never outlined boxes.

    private var verbBar: some View {
        HStack(spacing: 4) {
            Button { activeSheet = .getCased } label: {
                Text("Get cased now")
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
            }
            .buttonStyle(DSPressStyle())
            .background(Capsule().fill(palette.ink))

            Button { activeSheet = .caseSomeone } label: {
                Text("Case someone")
                    .font(.archivo(12, weight: 600))
                    .underline()
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button { activeSheet = .schedule } label: {
                Text("Schedule")
                    .font(.archivo(12, weight: 600))
                    .underline()
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .glassChip()
    }

    // MARK: - 2. Recap-gate card — the ONE glass hero on the screen (canvas 3b
    // line 1544 is glass: var(--gbg) + blur, 26px rounded corners — the verb
    // bar above is glass CHROME, not a hero; this card is the hero). Filled
    // "Read the recap" is the 2nd sanctioned filled-button exception.
    // RecapItem carries no serif "quote" field (interviewerName/grade/
    // caseTitle only), so the lede binds the case title rather than
    // fabricating persona-only feedback text — documented deviation.

    @ViewBuilder
    private var recapGateCard: some View {
        if let recap = viewModel.gateRecap {
            Button {
                AppRouter.shared.casePath.append(.recap(recap.sessionId))
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text("UNREAD RECAP — CLEARS BEFORE YOUR NEXT CASE")
                        .dsText(.kicker).foregroundStyle(palette.green)
                    Text(recap.caseTitle)
                        .dsText(.serif(14, italic: true)).foregroundStyle(palette.ink)
                    Text("\(recap.interviewerName) · \(Self.gradeText(recap.grade))")
                        .dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
                        .padding(.bottom, 5)
                    HStack(spacing: 14) {
                        Text("Read the recap")
                            .font(.archivo(12, weight: 600))
                            .foregroundStyle(palette.onInk)
                            .padding(.horizontal, 17)
                            .frame(height: 38)
                            .background(Capsule().fill(palette.ink))
                        Text("Interviewing and drills stay open.")
                            .dsText(.serif(11.5, italic: true)).foregroundStyle(palette.muted)
                    }
                }
                .padding(.horizontal, 19).padding(.vertical, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. NEXT UP — flat hairline block (canvas 3b 1554-1566), bound to
    // vm.nextUp (the soonest scheduled session) rather than a separate
    // recommendation entity — CaseTabViewModel has no recommendation field.
    // Swap is a cosmetic stub (the real swap-roles endpoint is F5's session
    // takeover) — wires the UI + a toast, per the T2 brief. The row restores
    // canvas 3b's leading status dot + right-aligned tabular countdown
    // (canvas ~1573-1579); nextUp is the single most-imminent session, so it
    // gets the green blink dot (keeps content greens ≤3 — the other is UPCOMING's
    // hollow ring, unlit).

    @ViewBuilder
    private var nextUpSection: some View {
        if let session = viewModel.nextUp {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("NEXT UP FOR YOU").dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer()
                    Button { toastMessage = "invite sent" } label: {
                        Text("Swap").font(.archivo(11, weight: 600)).underline().foregroundStyle(palette.muted)
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .center, spacing: 12) {
                    BlinkDot(diameter: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("vs \(session.otherUser) · \(session.caseTitle)")
                            .font(.archivo(16, weight: 700))
                            .foregroundStyle(palette.ink)
                        Text(Self.sessionMeta(session))
                            .dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 8)
                    if let countdown = CaseTabCopy.countdown(to: session.scheduledAt, now: Date()) {
                        Text(countdown)
                            .font(.archivo(10, weight: 600)).tracking(0.08 * 10).tabularNumbers()
                            .foregroundStyle(palette.muted)
                    }
                }
            }
            .padding(.top, 13).padding(.bottom, 4)
            .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
        }
    }

    // MARK: - 4. UPCOMING — flat rows (canvas 3b 1568-1599): leading hollow-
    // ring status dot + tabular countdown (canon chrome) PLUS an
    // add-to-calendar underline affordance (F3 brief's real EventKit
    // capability) — rise-in staggered (Motion.rise).

    @ViewBuilder
    private var upcomingSection: some View {
        if !viewModel.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("UPCOMING").dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer()
                    Text("ON YOUR CALENDAR")
                        .font(.archivo(8.5, weight: 600)).tracking(0.12 * 8.5)
                        .foregroundStyle(palette.muted)
                }
                .padding(.bottom, 2)
                ForEach(Array(viewModel.upcoming.enumerated()), id: \.element.id) { index, session in
                    upcomingRow(session)
                        .rise(upcomingAppeared, delay: Double(index) * DSMotion.stagger)
                }
            }
            .padding(.top, 13)
            .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
            .onAppear { upcomingAppeared = true }
        }
    }

    /// Hollow ring (canvas 3b: `border:1.5px solid #515A66`) — every UPCOMING
    /// row is an accepted-but-not-imminent session; only nextUp lights green.
    private var hollowRingDot: some View {
        Circle().strokeBorder(palette.muted, lineWidth: 1.5).frame(width: 7, height: 7)
    }

    private func upcomingRow(_ session: SessionSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            hollowRingDot
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(session.otherUser) · \(session.caseTitle)")
                    .dsText(.rowTitleStrong).foregroundStyle(palette.ink).lineLimit(1)
                Text(Self.sessionMeta(session)).dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let countdown = CaseTabCopy.countdown(to: session.scheduledAt, now: Date()) {
                    Text(countdown)
                        .font(.archivo(10, weight: 600)).tracking(0.08 * 10).tabularNumbers()
                        .foregroundStyle(palette.muted)
                }
                Button { Task { await viewModel.addToCalendar(session) } } label: {
                    Text("Add to calendar")
                        .font(.archivo(11, weight: 600)).underline().foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .bottom)
    }

    // MARK: - 5. PENDING — received rows w/ Accept/New time/Decline (canvas
    // 3b 1601-1631); sent-awaiting rows below, standard hairline, no actions.

    @ViewBuilder
    private var pendingSection: some View {
        if !viewModel.pendingReceived.isEmpty || !viewModel.sentAwaiting.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PENDING — \(viewModel.pendingReceived.count)").dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer()
                    Text("ONE COUNTER ROUND · NO CHAT")
                        .font(.archivo(8.5, weight: 600)).tracking(0.12 * 8.5)
                        .foregroundStyle(palette.muted)
                }
                .padding(.bottom, 2)
                ForEach(viewModel.pendingReceived) { proposal in
                    pendingRow(proposal)
                }
                ForEach(viewModel.sentAwaiting) { proposal in
                    sentAwaitingRow(proposal)
                }
            }
            .padding(.top, 13)
            .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
        }
    }

    private func pendingRow(_ proposal: Proposal) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CaseTabCopy.pendingOfferLabel(fromName: proposal.fromName, fromRole: proposal.fromRole))
                    .dsText(.rowTitleStrong).foregroundStyle(palette.ink)
                Text(Self.proposalMeta(proposal)).dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                Button { acceptProposal(proposal) } label: {
                    Text("Accept").font(.archivo(12.5, weight: 600)).underline().foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
                Button { counterTarget = proposal; counterDate = proposal.proposedTimes.first ?? Date() } label: {
                    Text("New time").font(.archivo(12.5, weight: 600)).underline().foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
                Button { Task { await viewModel.decline(proposal) } } label: {
                    Text("Decline").font(.archivo(12.5, weight: 600)).underline().foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .bottom)
    }

    /// Sent-and-awaiting rows: the same standard hairline as every other row
    /// (canvas 3b's sent row uses `border-bottom:1px solid #C9D2DF`, not a
    /// dashed rule — MINOR-3 review fix), verbatim "awaiting reply", no
    /// actions. Proposal carries no recipient-name field (only fromName — the
    /// sender), so the row leads with the case title rather than a
    /// fabricated "You → X" — documented deviation from canvas's `sentWho3`.
    private func sentAwaitingRow(_ proposal: Proposal) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.caseTitle ?? "Practice case").dsText(.rowTitleStrong).foregroundStyle(palette.ink)
                Text(Self.proposalMeta(proposal)).dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            Text("awaiting reply").dsText(.serif(12, italic: true)).foregroundStyle(palette.muted)
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .bottom)
    }

    private func acceptProposal(_ proposal: Proposal) {
        if proposal.proposedTimes.count > 1 {
            acceptChoiceProposal = proposal
        } else {
            let time = proposal.proposedTimes.first ?? Date()
            Task { await viewModel.accept(proposal, at: time) }
        }
    }

    // MARK: - 6. HISTORY — flat rows, greyed, tabular date (canvas 3b 1643-1666).

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("HISTORY").dsText(.kicker).foregroundStyle(palette.muted).padding(.bottom, 2)
                ForEach(viewModel.history) { session in
                    historyRow(session)
                }
            }
            .padding(.top, 13)
            .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
        }
    }

    private func historyRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.caseTitle).dsText(.rowTitle).foregroundStyle(palette.muted).lineLimit(1)
                Text("\(session.otherUser) · \(Self.historyDate(session.endedAt))")
                    .dsText(.meta).tabularNumbers().foregroundStyle(palette.faint)
            }
            Spacer(minLength: 8)
            if let grade = session.grade {
                Text(String(format: "%.1f", grade))
                    .font(.archivo(11, weight: 600)).tabularNumbers().foregroundStyle(palette.muted)
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: - 7. Empty state — undesigned but token-styled, terse (T2 brief).

    @ViewBuilder
    private var emptyState: some View {
        if visibility.isEmptyState {
            Text("Nothing cased yet — tap Get cased now to start.")
                .dsText(.serif(13, italic: true)).foregroundStyle(palette.muted)
                .padding(.top, 24)
        }
    }

    // MARK: - Formatting helpers

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static func sessionMeta(_ session: SessionSummary) -> String {
        guard let scheduledAt = session.scheduledAt else { return session.role }
        return "\(dateTimeFormatter.string(from: scheduledAt)) · \(session.role)"
    }

    private static func proposalMeta(_ proposal: Proposal) -> String {
        let time = proposal.proposedTimes.first.map { dateTimeFormatter.string(from: $0) } ?? "time TBD"
        if let caseType = proposal.caseType { return "\(caseType) · \(time)" }
        return time
    }

    private static func gradeText(_ grade: Double?) -> String {
        grade.map { String(format: "%.1f/5", $0) } ?? "—"
    }

    private static func historyDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return historyDateFormatter.string(from: date)
    }
}

// MARK: - Subviews

/// The canvas content rise: 16px up + fade, staggered by `delay` (Design
/// Decisions §1: "rise 420ms cubic-bezier(0.22,1,0.36,1) 16px up, staggered
/// ~120-150ms"). Mirrors GauntletRunView's private `rise(_:delay:)`.
private extension View {
    func rise(_ appeared: Bool, delay: Double) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(DSMotion.riseCurve.delay(delay), value: appeared)
    }
}

/// The verb-bar sheet placeholder shell — T3/T4/T5 replace the body per
/// their brief; the enum + `.sheet(item:)` seam in CaseTabView stays stable.
private struct CaseSheetPlaceholder: View {
    let kind: CaseSheet
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).dsText(.cardTitle).foregroundStyle(palette.ink)
            // MARK: T3/T4/T5 fills this — the real sheet body per its brief.
            Text("Coming soon.")
                .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
            Button { dismiss() } label: {
                Text("Close").dsText(.actionLabel).underline().foregroundStyle(palette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSheet()
        .padding(.horizontal, 14)
        .presentationBackground(.clear)
        .presentationDetents([.medium])
    }
}

/// "New time" — a compact DatePicker counters the pending proposal with one
/// alternate time (`vm.counter(_:times:)` — one counter round, per canvas).
private struct NewTimeSheet: View {
    let proposal: Proposal
    @Binding var date: Date
    let onSend: (Date) -> Void
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NEW TIME").dsText(.kicker).foregroundStyle(palette.muted)
            Text(proposal.caseTitle ?? "Practice case").dsText(.cardTitle).foregroundStyle(palette.ink)
            DatePicker("", selection: $date)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Button {
                onSend(date)
                dismiss()
            } label: {
                Text("Send").dsText(.rowTitle).foregroundStyle(palette.onInk)
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(DSPressStyle())
            .background(Capsule().fill(palette.ink))
            Button { dismiss() } label: {
                Text("Cancel").dsText(.actionLabel).underline().foregroundStyle(palette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSheet()
        .padding(.horizontal, 14)
        .presentationBackground(.clear)
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground(); CaseTabView(viewModel: CaseFixtures.makeViewModel()) }
}
#endif
