/*
 * Purpose: Renders the session's Live Activity — lock-screen banner and
 *          Dynamic Island (expanded/compact/minimal) — showing a lobby
 *          countdown to scheduledAt or the live-session elapsed timer since
 *          startedAt, plus the counterpart's name and session state.
 * Inputs: SessionActivityAttributes.ContentState pushed by the backend
 *         (Task 9) or set at Activity start (Task 10 LiveActivityController).
 * Outputs: none (widget UI only).
 * Run: built as part of the CaseRoomWidgets app-extension target, embedded
 *      in CaseRoom.app; on-device rendering verified manually (Task 12).
 */

import ActivityKit
import SwiftUI
import WidgetKit

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.counterpartName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(context: context)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(stateLabel(context.state.state))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "person.2.fill")
            } compactTrailing: {
                TimerText(context: context)
                    .font(.caption2)
            } minimal: {
                Image(systemName: "person.2.fill")
            }
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "lobby": return "In the lobby"
        case "live": return "Session live"
        default: return state.capitalized
        }
    }
}

private struct LockScreenBannerView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.counterpartName)
                    .font(.headline)
                Text(stateLabel(context.state.state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TimerText(context: context)
                .font(.title3)
                .monospacedDigit()
        }
        .padding()
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "lobby": return "In the lobby"
        case "live": return "Session live"
        default: return state.capitalized
        }
    }
}

// Renders a client-side ticking timer — a countdown to scheduledAt while in
// the lobby, or the elapsed time since startedAt once live. Text(timerInterval:)
// ticks locally on-device; it does not depend on a fresh push every second.
private struct TimerText: View {
    // Hoisted: ISO8601DateFormatter is expensive to construct, and body can
    // render many times per second. Default options (no fractional seconds) —
    // the backend truncates microseconds before pushing.
    private static let isoFormatter = ISO8601DateFormatter()

    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        if context.state.state == "live", let startedAt = date(context.state.startedAt) {
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
        } else if let scheduledAt = date(context.state.scheduledAt) {
            Text(timerInterval: Date()...scheduledAt, countsDown: true)
        } else {
            Text(context.state.state.capitalized)
        }
    }

    private func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return Self.isoFormatter.date(from: iso)
    }
}

@main
struct CaseRoomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
        StreakWidget()
        NextSessionWidget()
        FreeNowWidget()
    }
}
