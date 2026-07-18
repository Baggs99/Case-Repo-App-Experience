/*
 * Purpose: Steering-source parsing + the app-side App Intents. DeepLink folds the
 *          caseroom:// URL and PushRoute steering sources (their parsers/tests are
 *          behavior-preserved); AppRouter is the central router that maps every
 *          steering source onto the pinned AppRoute registry; plus StartDrillIntent,
 *          NextSessionIntent, and the CaseRoomShortcuts provider.
 * Inputs: PushRoute payloads, caseroom:// URLs, APIClient.shared.dashboard().
 * Outputs: AppRouter.shared mutations (observed by RootShell); a spoken dialog.
 * Run: intents run by the system; RootShell observes AppRouter + .onOpenURL.
 */

import AppIntents
import Foundation
import Observation

// Steering-source parse result (was `AppRoute` pre-F1). Covers the caseroom://
// deep links and the notification-tap fold. AppRouter maps these onto AppRoute.
enum DeepLink: Equatable {
    case drill
    case sessions
    case proposeTo(Int)
    case freeNow

    // Folds a notification-tap PushRoute. Both `.proposals` and `.session` land
    // on the sessions surface (the prior behavior).
    init(_ pushRoute: PushRoute) {
        switch pushRoute {
        case .proposals, .session:
            self = .sessions
        case .proposeTo(let userId):
            self = .proposeTo(userId)
        }
    }

    // Pure caseroom:// parser (covers the widget deep links). Unknown host or a
    // non-caseroom scheme -> nil (ignored by the caller).
    static func route(from url: URL) -> DeepLink? {
        guard url.scheme == "caseroom" else { return nil }
        switch url.host {
        case "drill": return .drill
        case "sessions": return .sessions
        case "freenow": return .freeNow
        default: return nil
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    // Tab + navigation state observed by RootShell.
    var selection: DSTab = .home
    var avatarSheet = false
    var groupCreate = false
    var proposeToUserID: Int?
    var sessionTakeoverID: Int?

    // MARK: F3 case-prefill — the F4 library CTA sets one of these + selects the
    // Case tab; CaseTabView consumes it to open the matching verb-bar sheet with
    // the case pre-filled, then clears it. Router STATE only (mirrors
    // groupCreate/proposeToUserID) — no go()/App-Intent/deep-link involvement.
    var caseSomeonePrefillCaseID: Int?    // done case → "Case someone with this"
    var caseSomeonePrefillTitle: String?  // carried case title for that context
    var caseGetCasedPrefillCaseID: Int?   // open case → "Get cased on this"
    var drillRun = false          // the shell owns the drill sheet, keyed off this
    var gauntletRun = false       // shell owns the gauntlet fullScreenCover, keyed off this (F7 Task 4)
    // "See today's result" seam (F7 Task 4): DrillsView sets the already-scored
    // result before flagging gauntletRun so the cover opens straight into the
    // result phase (B8 blocks a re-run). Cleared with the flag on dismiss.
    var gauntletResult: GauntletResult?
    var homePath: [AppRoute] = []
    var libraryPath: [AppRoute] = []
    var casePath: [AppRoute] = []
    var communityPath: [AppRoute] = []

    /// Intent inbox: an App Intent (which can't reach the SwiftUI environment)
    /// sets this; RootShell drains it via go(to:) then clears it back to nil.
    var pending: AppRoute?

    private init() {}

    /// Navigate to any AppRoute. Detail routes select the owning tab and push
    /// onto its stack; modal/cover routes flip their presentation flag; drillRun
    /// opens the (transitionally Home-hosted) drill sheet.
    func go(to route: AppRoute) {
        switch route {
        case .home, .library, .caseTab, .community, .drills:
            if let tab = route.owningTab { selection = tab }
        case .avatarSheet:
            avatarSheet = true
        case .sessionTakeover(let id):
            sessionTakeoverID = id
        case .drillRun:
            selection = .home
            drillRun = true       // RootShell observes this and presents DrillView
        case .gauntletRun:
            gauntletRun = true    // RootShell observes this and presents GauntletRunView (Task 4)
        case .caseDetail(let id):
            selection = .library
            libraryPath.append(.caseDetail(id))
        case .timelineDetail:
            selection = .home
            homePath.append(.timelineDetail)
        case .recap:
            selection = .caseTab // F5 wires the recap presentation
        case .groupPage:
            selection = .community // F8 wires the group-page push onto communityPath
        }
    }

    /// Remap a parsed caseroom:// / push-fold steering source onto the router.
    func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .drill:              go(to: .drillRun)
        case .sessions, .freeNow: go(to: .caseTab)
        case .proposeTo(let id):
            selection = .caseTab
            proposeToUserID = id
        }
    }

    /// Remap a raw notification-tap PushRoute onto the router (via DeepLink).
    func handlePush(_ route: PushRoute) {
        handleDeepLink(DeepLink(route))
    }
}

struct StartDrillIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Drill"
    static let description = IntentDescription("Open today's practice drill.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.pending = .drillRun }
        return .result()
    }
}

struct NextSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Session"
    static let description = IntentDescription("Hear when your next practice session is.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await Self.run { try await APIClient.shared.dashboard() }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }

    /// Injectable seam: composes the spoken dialog from a fetched dashboard.
    /// Never throws — a failed fetch (logged out, offline) becomes a spoken
    /// failure line instead of a generic Siri error, matching
    /// ToggleFreeNowIntent's perform()-never-throws principle.
    static func run(fetch: () async throws -> DashboardStats) async -> String {
        do {
            return dialogText(for: try await fetch())
        } catch {
            return failureDialogText
        }
    }

    static let failureDialogText = "Couldn't reach CaseRoom — open the app and try again."

    /// Pure dialog composition — the unit-tested core.
    static func dialogText(for stats: DashboardStats) -> String {
        guard let next = stats.nextSession else {
            return "Nothing scheduled. Say 'I'm free now' to find a partner."
        }
        return "Next: \(next.caseTitle) with \(next.otherUser), \(relativeTime(for: next.scheduledAt))."
    }

    private static func relativeTime(for date: Date?) -> String {
        guard let date else { return "soon" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CaseRoomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDrillIntent(),
            phrases: ["Start a drill in \(.applicationName)"],
            shortTitle: "Start Drill",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: NextSessionIntent(),
            phrases: ["What's my next session in \(.applicationName)"],
            shortTitle: "Next Session",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: ToggleFreeNowIntent(),
            phrases: ["I'm free now in \(.applicationName)"],
            shortTitle: "Free Now",
            systemImageName: "bolt.fill"
        )
    }
}
