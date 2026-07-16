/*
 * Purpose: Unit tests for WidgetTimeline.entries/refreshDate — the pure
 *          widget-timeline logic: single entry when nothing is scheduled,
 *          ascending session boundary entries (now / -15m / at-time, past
 *          boundaries dropped), freeUntil boundary, and the 30m refresh date.
 * Inputs: none (constructs WidgetSnapshot values with a fixed "now").
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import WidgetKit
import XCTest
@testable import CaseRoom

final class WidgetTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(nextAt: Date? = nil, freeUntil: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(
            streakDays: 5,
            drillDoneToday: false,
            nextSessionTitle: "Widget Co Profitability",
            nextSessionOther: "Sam Case",
            nextSessionAt: nextAt,
            freeUntil: freeUntil,
            updatedAt: now
        )
    }

    func testNilSnapshotYieldsSinglePlaceholderEntry() {
        let entries = WidgetTimeline.entries(from: nil, now: now)
        XCTAssertEqual(entries.map(\.date), [now])
        XCTAssertNil(entries[0].snapshot)
    }

    func testNoNextSessionYieldsSingleEntry() {
        let entries = WidgetTimeline.entries(from: snapshot(), now: now)
        XCTAssertEqual(entries.map(\.date), [now])
        XCTAssertNotNil(entries[0].snapshot)
    }

    func testSessionInTwoHoursYieldsThreeAscendingEntries() {
        let at = now.addingTimeInterval(2 * 3600)
        let entries = WidgetTimeline.entries(from: snapshot(nextAt: at), now: now)
        let dates = entries.map(\.date)
        XCTAssertEqual(dates, [now, at.addingTimeInterval(-15 * 60), at])
        XCTAssertEqual(dates, dates.sorted())
    }

    func testSessionWithinFifteenMinutesDropsPastLeadBoundary() {
        let at = now.addingTimeInterval(10 * 60)
        let entries = WidgetTimeline.entries(from: snapshot(nextAt: at), now: now)
        XCTAssertEqual(entries.map(\.date), [now, at])
    }

    func testPastSessionYieldsNoExtraEntries() {
        let at = now.addingTimeInterval(-3600)
        let entries = WidgetTimeline.entries(from: snapshot(nextAt: at), now: now)
        XCTAssertEqual(entries.map(\.date), [now])
    }

    func testFreeUntilFutureAddsBoundaryEntry() {
        let free = now.addingTimeInterval(30 * 60)
        let entries = WidgetTimeline.entries(from: snapshot(freeUntil: free), now: now)
        XCTAssertEqual(entries.map(\.date), [now, free])
    }

    func testFreeUntilPastAddsNoBoundary() {
        let free = now.addingTimeInterval(-600)
        let entries = WidgetTimeline.entries(from: snapshot(freeUntil: free), now: now)
        XCTAssertEqual(entries.map(\.date), [now])
    }

    func testSessionAndFreeUntilMergeSortedAscending() {
        let at = now.addingTimeInterval(2 * 3600)
        let free = now.addingTimeInterval(30 * 60)
        let entries = WidgetTimeline.entries(from: snapshot(nextAt: at, freeUntil: free), now: now)
        XCTAssertEqual(entries.map(\.date), [now, free, at.addingTimeInterval(-15 * 60), at])
    }

    func testAllEntriesShareTheSourceSnapshot() {
        let at = now.addingTimeInterval(2 * 3600)
        let snap = snapshot(nextAt: at)
        let entries = WidgetTimeline.entries(from: snap, now: now)
        XCTAssertEqual(entries.count, 3)
        for entry in entries { XCTAssertEqual(entry.snapshot, snap) }
    }

    func testRefreshDateIsThirtyMinutesAfterNow() {
        XCTAssertEqual(WidgetTimeline.refreshDate(after: now), now.addingTimeInterval(30 * 60))
    }
}
