/*
 * Purpose: Pin the persona fixture values to Decisions §3 (phone/Jul 16) and §7
 *          (tablet/Jul 17 day-advance) so later phases' previews stay canonical.
 * Inputs: PreviewFixtures.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/PreviewFixturesTests
 */

import XCTest
@testable import CaseRoom

final class PreviewFixturesTests: XCTestCase {
    func testPhoneMatchesDecisionsSection3() {
        let d = PreviewFixtures.phone
        XCTAssertEqual(d.profile.initials, "AO")
        XCTAssertEqual(d.profile.cohort, "C-14")
        XCTAssertEqual(d.profile.streakDays, 12)
        XCTAssertEqual(d.profile.points, 331)
        XCTAssertEqual(d.diagnostic.marketSizing, 5.1, accuracy: 0.001)
        XCTAssertEqual(d.diagnostic.focus, "Market sizing")
        XCTAssertEqual(d.tonight.opponent, "M. Lindqvist")
        XCTAssertEqual(d.tonight.time, "19:00")
        XCTAssertEqual(d.recap.interviewer, "T. Becker")
        XCTAssertEqual(d.timeline.first?.readiness, "ON PACE")
        XCTAssertTrue(d.timeline.first!.onPace)
        XCTAssertFalse(d.timeline[1].onPace)   // only McKinsey is green
        XCTAssertEqual(d.standing.schoolPercentile, 91)
    }

    func testTabletIsOneDayAdvanced() {
        let d = PreviewFixtures.tablet
        XCTAssertEqual(d.profile.streakDays, 13)
        XCTAssertEqual(d.profile.points, 335)
        XCTAssertEqual(d.profile.behindNext, 4)
        XCTAssertEqual(d.diagnostic.quant, 6.6, accuracy: 0.001)
        XCTAssertEqual(d.diagnostic.marketSizing, 5.3, accuracy: 0.001)
        XCTAssertEqual(d.diagnostic.casesLogged, 15)
        XCTAssertEqual(d.tonight.caseTitle, "Dental roll-up")
        XCTAssertEqual(d.standing.schoolPercentile, 88)
        XCTAssertEqual(d.timeline.first?.days, "57 days")
    }
}
