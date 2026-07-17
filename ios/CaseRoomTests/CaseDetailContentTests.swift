/*
 * Purpose: Unit tests for LibraryDetailCopy — the pure tag/CTA/note/history/
 *          layout derivations behind CaseDetailContent (canvas 5a detail /
 *          2c right pane). Prefers these over SwiftUI view snapshots per the
 *          Task 4 brief; LibraryCase.detailMeta itself is already covered by
 *          LibraryViewModelTests (Task 2), not re-tested here.
 * Inputs: none (pure function calls).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class CaseDetailContentTests: XCTestCase {

    // MARK: - Tag (libDTag/libDTagColor)

    func testTagRecommendedWinsGreen() {
        let tag = LibraryDetailCopy.tag(recommended: true, done: false)
        XCTAssertEqual(tag.text, "RECOMMENDED FOR YOU")
        XCTAssertTrue(tag.isGreen)
    }

    func testTagRecommendedWinsOverDoneToo() {
        // The canvas checks `rec` before `done` — a fixture could carry both;
        // recommendation still takes priority.
        let tag = LibraryDetailCopy.tag(recommended: true, done: true)
        XCTAssertEqual(tag.text, "RECOMMENDED FOR YOU")
        XCTAssertTrue(tag.isGreen)
    }

    func testTagDoneRetiredFaint() {
        let tag = LibraryDetailCopy.tag(recommended: false, done: true)
        XCTAssertEqual(tag.text, "DONE — RETIRED FOR YOU")
        XCTAssertFalse(tag.isGreen)
    }

    func testTagOpenFaint() {
        let tag = LibraryDetailCopy.tag(recommended: false, done: false)
        XCTAssertEqual(tag.text, "OPEN FOR YOU")
        XCTAssertFalse(tag.isGreen)
    }

    // MARK: - CTA (libDCta)

    func testCtaFlipsWithDone() {
        XCTAssertEqual(LibraryDetailCopy.cta(done: false), "Get cased on this")
        XCTAssertEqual(LibraryDetailCopy.cta(done: true), "Case someone with this")
    }

    // MARK: - Note (libDNote)

    func testNoteFlipsWithDone() {
        XCTAssertEqual(LibraryDetailCopy.note(done: false), "Opens the Case tab with this case pre-filled.")
        XCTAssertEqual(
            LibraryDetailCopy.note(done: true),
            "Done cases join your interviewer deck — you know the answer key now."
        )
    }

    // MARK: - History (libDHist/libDHistScore) — title-matched

    private func session(
        title: String, otherUser: String = "M. Lindqvist",
        endedAt: Date?, grade: Double?
    ) -> SessionSummary {
        SessionSummary(
            id: Int.random(in: 1...9999), role: "candidate", otherUser: otherUser,
            caseTitle: title, scheduledAt: nil, state: "done", endedAt: endedAt, grade: grade
        )
    }

    private func utcDate(_ yyyyMMdd: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Local timezone (matches the product's history formatter): building the
        // date at LOCAL midnight and formatting it in the LOCAL zone yields the
        // same calendar date on any host, so the "Jul 16" assertions are
        // deterministic off-UTC (e.g. a US Mac) rather than rolling back a day.
        formatter.timeZone = .current
        return formatter.date(from: yyyyMMdd)!
    }

    func testHistoryNilWhenNoTitleMatch() {
        let sessions = [session(title: "Some other case", endedAt: utcDate("2026-07-01"), grade: 4.0)]
        let history = LibraryDetailCopy.history(from: sessions, caseTitle: "Nordic carrier")
        XCTAssertNil(history.line)
        XCTAssertNil(history.score)
    }

    func testHistoryLineAndScoreOnMatch() {
        let sessions = [
            session(title: "Nordic carrier", otherUser: "M. Lindqvist", endedAt: utcDate("2026-07-16"), grade: 7.2),
        ]
        let history = LibraryDetailCopy.history(from: sessions, caseTitle: "Nordic carrier")
        XCTAssertEqual(history.line, "Jul 16 · M. Lindqvist")
        XCTAssertEqual(history.score, "7.2 avg")
    }

    func testHistoryScoreNilWhenGradeNil() {
        let sessions = [session(title: "Nordic carrier", endedAt: utcDate("2026-07-16"), grade: nil)]
        let history = LibraryDetailCopy.history(from: sessions, caseTitle: "Nordic carrier")
        XCTAssertEqual(history.line, "Jul 16 · M. Lindqvist")
        XCTAssertNil(history.score)
    }

    func testHistoryPicksMostRecentTitleMatch() {
        let sessions = [
            session(title: "Nordic carrier", otherUser: "Older Partner", endedAt: utcDate("2026-06-01"), grade: 3.0),
            session(title: "Nordic carrier", otherUser: "Newer Partner", endedAt: utcDate("2026-07-16"), grade: 7.2),
            session(title: "Unrelated case", otherUser: "Ignore Me", endedAt: utcDate("2026-07-17"), grade: 9.9),
        ]
        let history = LibraryDetailCopy.history(from: sessions, caseTitle: "Nordic carrier")
        XCTAssertEqual(history.line, "Jul 16 · Newer Partner")
        XCTAssertEqual(history.score, "7.2 avg")
    }

    func testHistoryEmptySessionsReturnsNil() {
        let history = LibraryDetailCopy.history(from: [], caseTitle: "Nordic carrier")
        XCTAssertNil(history.line)
        XCTAssertNil(history.score)
    }

    // MARK: - Layout deltas (plan item 12)

    func testTitleAndRatingSizePhoneVsTablet() {
        XCTAssertEqual(LibraryDetailCopy.titleSize(layout: .phone), 24)
        XCTAssertEqual(LibraryDetailCopy.titleSize(layout: .tablet), 22)
        XCTAssertEqual(LibraryDetailCopy.ratingSize(layout: .phone), 26)
        XCTAssertEqual(LibraryDetailCopy.ratingSize(layout: .tablet), 24)
    }

    func testCasePackSubDropsInterviewerSideSuffixOnTablet() {
        XCTAssertEqual(
            LibraryDetailCopy.casePackSub(layout: .phone),
            "Prompt script, exhibits, answer key — interviewer side"
        )
        XCTAssertEqual(LibraryDetailCopy.casePackSub(layout: .tablet), "Prompt script, exhibits, answer key")
    }

    func testKnowsAsideIsPhoneOnly() {
        XCTAssertTrue(LibraryDetailCopy.showsKnowsAside(layout: .phone))
        XCTAssertFalse(LibraryDetailCopy.showsKnowsAside(layout: .tablet))
    }

    func testRecasedAfterthoughtIsPhoneOnlyAndDoneOnly() {
        XCTAssertTrue(LibraryDetailCopy.showsRecasedAfterthought(layout: .phone, done: true))
        XCTAssertFalse(LibraryDetailCopy.showsRecasedAfterthought(layout: .phone, done: false))
        XCTAssertFalse(LibraryDetailCopy.showsRecasedAfterthought(layout: .tablet, done: true))
        XCTAssertFalse(LibraryDetailCopy.showsRecasedAfterthought(layout: .tablet, done: false))
    }
}
