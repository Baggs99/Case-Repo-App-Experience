/*
 * Purpose: Pure, testable timeline logic for the habit widgets — turns a
 *          WidgetSnapshot into ordered render entries (now plus each future
 *          boundary moment so relative times and free/not-free state flip
 *          without waking the app) and the 30-minute refresh backstop date.
 * Inputs: an optional WidgetSnapshot and the current Date ("now").
 * Outputs: [SnapshotEntry] ascending by date; refreshDate(after:).
 * Run: WidgetTimeline.entries(from: SnapshotStore.read(), now: Date()).
 */

import Foundation
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

enum WidgetTimeline {
    // Minutes before a session at which to add a "starting soon" render entry.
    private static let sessionLeadTime: TimeInterval = 15 * 60
    private static let refreshInterval: TimeInterval = 30 * 60

    /// One entry at `now`, plus a render entry at each still-future boundary
    /// moment — session-15m, session start, freeUntil — so WidgetKit re-renders
    /// when the display should change (relative countdown, free→not-free flip)
    /// without waking the app. Boundaries are ascending and de-duplicated;
    /// past ones are dropped. A nil snapshot yields a single placeholder entry.
    static func entries(from snapshot: WidgetSnapshot?, now: Date) -> [SnapshotEntry] {
        guard let snapshot else { return [SnapshotEntry(date: now, snapshot: nil)] }

        var boundaries: [Date] = []
        if let at = snapshot.nextSessionAt {
            boundaries.append(at.addingTimeInterval(-sessionLeadTime))
            boundaries.append(at)
        }
        if let freeUntil = snapshot.freeUntil {
            boundaries.append(freeUntil)
        }

        let future = boundaries
            .filter { $0 > now }
            .sorted()
            .reduce(into: [Date]()) { unique, date in
                if unique.last != date { unique.append(date) }
            }

        return ([now] + future).map { SnapshotEntry(date: $0, snapshot: snapshot) }
    }

    /// WidgetKit requests a fresh timeline after this date. The app also reloads
    /// widgets on state changes (Task 10), so this is only a backstop.
    static func refreshDate(after now: Date) -> Date {
        now.addingTimeInterval(refreshInterval)
    }
}
