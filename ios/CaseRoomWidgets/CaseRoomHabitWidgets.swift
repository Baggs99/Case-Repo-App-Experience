/*
 * Purpose: The three home/lock-screen habit widgets — Streak, Next Session,
 *          and Free Now — plus the shared TimelineProvider that reads the App
 *          Group snapshot and delegates entry scheduling to WidgetTimeline.
 * Inputs: SnapshotStore.read() (widget-snapshot.json in the App Group).
 * Outputs: none (widget UI + tap deep links only).
 * Run: built into the CaseRoomWidgets extension; added to CaseRoomWidgetsBundle.
 */

import SwiftUI
import WidgetKit

// MARK: - Shared provider

// All three widgets render from the same snapshot, so they share one provider;
// only the views differ.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : SnapshotStore.read()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entries = WidgetTimeline.entries(from: SnapshotStore.read(), now: now)
        completion(Timeline(entries: entries, policy: .after(WidgetTimeline.refreshDate(after: now))))
    }
}

// MARK: - Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaseRoomStreak", provider: SnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .widgetURL(URL(string: "caseroom://drill")!)
        }
        .configurationDisplayName("Drill Streak")
        .description("Your daily drill streak at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                SignInPlaceholder()
            }
        }
        .widgetContainerBackground(family)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: snapshot.drillDoneToday ? "flame.fill" : "flame")
                        .font(.caption)
                    Text("\(snapshot.streakDays)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
            }
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: snapshot.drillDoneToday ? "flame.fill" : "flame")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("\(snapshot.streakDays)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(snapshot.streakDays == 1 ? "day streak" : "days streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if snapshot.drillDoneToday {
                    Label("Done today", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("Tap to drill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Next session

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaseRoomNextSession", provider: SnapshotProvider()) { entry in
            NextSessionWidgetView(entry: entry)
                .widgetURL(URL(string: "caseroom://sessions")!)
        }
        .configurationDisplayName("Next Session")
        .description("Your next scheduled practice session.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct NextSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                SignInPlaceholder()
            }
        }
        .widgetContainerBackground(family)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        if let at = snapshot.nextSessionAt {
            scheduled(snapshot, at: at)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func scheduled(_ snapshot: WidgetSnapshot, at: Date) -> some View {
        let isAccessory = family == .accessoryRectangular
        VStack(alignment: .leading, spacing: isAccessory ? 1 : 4) {
            Text("Next session")
                .font(isAccessory ? .caption2 : .caption)
                .foregroundStyle(.secondary)
            Text(snapshot.nextSessionTitle ?? "Practice session")
                .font(.headline)
                .lineLimit(2)
            if let other = snapshot.nextSessionOther {
                Text("with \(other)")
                    .font(isAccessory ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(at, style: .relative)
                .font(isAccessory ? .caption2 : .footnote)
                .foregroundStyle(isAccessory ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetAccentable(isAccessory)
    }

    @ViewBuilder
    private var empty: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text("No session scheduled")
                    .font(.headline)
                Text("Propose one")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No session scheduled — propose one")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Free now

struct FreeNowWidget: Widget {
    var body: some WidgetConfiguration {
        // swapped to Button(intent:) in the intents task
        StaticConfiguration(kind: "CaseRoomFreeNow", provider: SnapshotProvider()) { entry in
            FreeNowWidgetView(entry: entry)
                .widgetURL(URL(string: "caseroom://freenow")!)
        }
        .configurationDisplayName("Free Now")
        .description("Show your partner you're free to practice.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct FreeNowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    // Free until a future moment relative to this entry's render time; the
    // timeline adds a boundary entry at freeUntil so this flips automatically.
    private var isFree: Bool {
        guard let freeUntil = entry.snapshot?.freeUntil else { return false }
        return freeUntil > entry.date
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                SignInPlaceholder()
            }
        }
        .widgetContainerBackground(family)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: isFree ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
            }
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: isFree ? "bolt.fill" : "bolt.slash")
                    .font(.title)
                    .foregroundStyle(isFree ? .green : .secondary)
                Text(isFree ? "Free now" : "Not free")
                    .font(.headline)
                Spacer(minLength: 0)
                if isFree, let freeUntil = snapshot.freeUntil {
                    HStack(spacing: 2) {
                        Text("for")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(freeUntil, style: .timer)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                } else {
                    Text("Tap to go free")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared views + helpers

private struct SignInPlaceholder: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
        case .accessoryRectangular:
            Label("Open CaseRoom to sign in", systemImage: "person.crop.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open CaseRoom to sign in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension View {
    // iOS 17 widgets must declare their container background; accessory
    // (lock-screen) widgets stay transparent so the system tints them.
    @ViewBuilder
    func widgetContainerBackground(_ family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            containerBackground(for: .widget) { Color.clear }
        default:
            containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }
}

extension WidgetSnapshot {
    // Gallery/preview sample so the widget picker shows populated content.
    static var sample: WidgetSnapshot {
        WidgetSnapshot(
            streakDays: 7,
            drillDoneToday: true,
            nextSessionTitle: "Widget Co Profitability",
            nextSessionOther: "Jordan",
            nextSessionAt: Date().addingTimeInterval(2 * 3600),
            freeUntil: Date().addingTimeInterval(30 * 60),
            updatedAt: Date()
        )
    }
}
