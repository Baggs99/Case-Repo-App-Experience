/*
 * Purpose: In-app routing target for intents/deep-links plus the app-side App
 *          Intents — AppRoute (the folded PushRoute + URL destinations),
 *          AppRouter (a router singleton RootTabView observes), StartDrillIntent,
 *          NextSessionIntent, and the CaseRoomShortcuts provider.
 * Inputs: PushRoute payloads, caseroom:// URLs, APIClient.shared.dashboard().
 * Outputs: AppRouter.shared.pending mutations; a spoken/next-session dialog.
 * Run: intents run by the system; RootTabView observes AppRouter + .onOpenURL.
 */

import AppIntents
import Foundation
import Observation

// One destination type for every way the app gets steered: notification taps
// (PushRoute), caseroom:// deep links, and App Intents. RootTabView switches on
// this alone, so there is a single routing path.
enum AppRoute: Equatable {
    case drill
    case sessions
    case proposeTo(Int)
    case freeNow

    // Folds a notification-tap PushRoute into an AppRoute. Both `.proposals` and
    // `.session` land on the Sessions tab (the prior RootTabView behavior).
    init(_ pushRoute: PushRoute) {
        switch pushRoute {
        case .proposals, .session:
            self = .sessions
        case .proposeTo(let userId):
            self = .proposeTo(userId)
        }
    }

    // Pure caseroom:// parser (covers the Task-8 widget deep links). Unknown
    // host or a non-caseroom scheme -> nil (ignored by the caller).
    static func route(from url: URL) -> AppRoute? {
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

    /// Set by an intent (or any in-process caller) to request navigation;
    /// RootTabView observes this, acts, then clears it back to nil.
    var pending: AppRoute?

    private init() {}
}

struct StartDrillIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Drill"
    static let description = IntentDescription("Open today's practice drill.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.pending = .drill }
        return .result()
    }
}

struct NextSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Session"
    static let description = IntentDescription("Hear when your next practice session is.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await Self.run { try await APIClient.shared.dashboard() }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }

    /// Injectable seam: composes the spoken dialog from a fetched dashboard.
    /// Keeps perform() a one-liner while letting tests drive the fetch.
    static func run(fetch: () async throws -> DashboardStats) async throws -> String {
        dialogText(for: try await fetch())
    }

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
