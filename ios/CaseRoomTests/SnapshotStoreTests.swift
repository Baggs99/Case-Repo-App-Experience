/*
 * Purpose: Unit tests for SnapshotStore/WidgetSnapshot — write→read round-trip
 *          equality through the App Group container, clear() → nil, and
 *          nil-container safety (no crash when the group container is absent).
 * Inputs: none (writes/reads widget-snapshot.json in the group container).
 * Outputs: none (cleans up the snapshot file it writes).
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class SnapshotStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotStore.clear()
    }

    override func tearDown() {
        SnapshotStore.clear()
        super.tearDown()
    }

    // Dates are floored to whole seconds: the store serializes ISO8601 without
    // fractional seconds (matching the widget's decoder), so sub-second
    // precision would not survive a round-trip and break equality.
    private func fixedSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            streakDays: 7,
            drillDoneToday: true,
            nextSessionTitle: "Widget Co Profitability",
            nextSessionOther: "Bob Dev",
            nextSessionAt: Date(timeIntervalSince1970: 1_800_000_000),
            freeUntil: Date(timeIntervalSince1970: 1_800_003_600),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testWriteReadRoundTripEquality() throws {
        try XCTSkipIf(
            AppGroup.containerURL == nil,
            "App Group container did not resolve in this sim — round-trip covered on provisioned builds; nil path exercised by testNilContainerSafeNoCrash."
        )
        let snapshot = fixedSnapshot()

        SnapshotStore.write(snapshot)
        let readBack = SnapshotStore.read()

        XCTAssertEqual(readBack, snapshot)
    }

    func testClearThenReadReturnsNil() throws {
        try XCTSkipIf(AppGroup.containerURL == nil, "App Group container did not resolve in this sim.")
        SnapshotStore.write(fixedSnapshot())
        XCTAssertNotNil(SnapshotStore.read())

        SnapshotStore.clear()

        XCTAssertNil(SnapshotStore.read())
    }

    // Cannot force a nil container in the sim, so this asserts the public API
    // never crashes and behaves sanely regardless of whether the container
    // resolved. When it did not resolve, write is a no-op and read is nil;
    // when it did, clear() leaves read nil. Either way: no crash, read == nil.
    func testNilContainerSafeNoCrash() {
        SnapshotStore.write(fixedSnapshot())
        SnapshotStore.clear()

        XCTAssertNil(SnapshotStore.read())
    }

    func testNextSessionFieldsOptionalRoundTrip() throws {
        try XCTSkipIf(AppGroup.containerURL == nil, "App Group container did not resolve in this sim.")
        let snapshot = WidgetSnapshot(
            streakDays: 0,
            drillDoneToday: false,
            nextSessionTitle: nil,
            nextSessionOther: nil,
            nextSessionAt: nil,
            freeUntil: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        SnapshotStore.write(snapshot)

        XCTAssertEqual(SnapshotStore.read(), snapshot)
    }
}
