/*
 * Purpose: Unit tests for CaseTabView's pure helpers — CaseTabSectionVisibility
 *          (which kicker+block sections show, given a VM data snapshot),
 *          CaseTabCopy.pendingOfferLabel (the Accept-row copy branch), and
 *          CaseTabGateSteering (the "append .recap + clear the gate" side
 *          effect, extracted from the `.onChange(of: gatedRecapSessionID)`
 *          handler so it's testable without rendering SwiftUI). Prefers these
 *          pure-helper tests over SwiftUI view snapshots, mirroring
 *          CaseDetailContentTests.
 * Inputs: none (pure function calls).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
import SwiftUI
@testable import CaseRoom

final class CaseTabViewTests: XCTestCase {

    // MARK: - CaseTabSectionVisibility

    func testAllSectionsShowWhenDataPresent() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: true, hasNextUp: true,
            upcomingCount: 1, pendingReceivedCount: 1, sentAwaitingCount: 1, historyCount: 1
        )
        XCTAssertTrue(visibility.showsRecapGate)
        XCTAssertTrue(visibility.showsNextUp)
        XCTAssertTrue(visibility.showsUpcoming)
        XCTAssertTrue(visibility.showsPending)
        XCTAssertTrue(visibility.showsHistory)
        XCTAssertFalse(visibility.isEmptyState)
    }

    func testAllSectionsHideWhenDataAbsent() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: false, hasNextUp: false,
            upcomingCount: 0, pendingReceivedCount: 0, sentAwaitingCount: 0, historyCount: 0
        )
        XCTAssertFalse(visibility.showsRecapGate)
        XCTAssertFalse(visibility.showsNextUp)
        XCTAssertFalse(visibility.showsUpcoming)
        XCTAssertFalse(visibility.showsPending)
        XCTAssertFalse(visibility.showsHistory)
        XCTAssertTrue(visibility.isEmptyState)
    }

    func testPendingShowsOnSentAwaitingAloneEvenWithNoReceivedOffers() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: false, hasNextUp: false,
            upcomingCount: 0, pendingReceivedCount: 0, sentAwaitingCount: 1, historyCount: 0
        )
        XCTAssertTrue(visibility.showsPending)
        XCTAssertFalse(visibility.isEmptyState)
    }

    func testPendingShowsOnReceivedAloneEvenWithNoSentAwaiting() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: false, hasNextUp: false,
            upcomingCount: 0, pendingReceivedCount: 1, sentAwaitingCount: 0, historyCount: 0
        )
        XCTAssertTrue(visibility.showsPending)
    }

    func testEmptyStateFalseWhenOnlyRecapGateShows() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: true, hasNextUp: false,
            upcomingCount: 0, pendingReceivedCount: 0, sentAwaitingCount: 0, historyCount: 0
        )
        XCTAssertFalse(visibility.isEmptyState)
    }

    func testEmptyStateFalseWhenOnlyHistoryShows() {
        let visibility = CaseTabSectionVisibility.compute(
            hasGateRecap: false, hasNextUp: false,
            upcomingCount: 0, pendingReceivedCount: 0, sentAwaitingCount: 0, historyCount: 3
        )
        XCTAssertFalse(visibility.isEmptyState)
        XCTAssertTrue(visibility.showsHistory)
        XCTAssertFalse(visibility.showsUpcoming)
    }

    // MARK: - CaseTabCopy.countdown (canon "T-6H"/"T-3D" style, tabular)

    func testCountdownNilWhenNoDate() {
        XCTAssertNil(CaseTabCopy.countdown(to: nil, now: Date()))
    }

    func testCountdownNowWhenAtOrPastDeadline() {
        let now = Date()
        XCTAssertEqual(CaseTabCopy.countdown(to: now, now: now), "NOW")
        XCTAssertEqual(CaseTabCopy.countdown(to: now.addingTimeInterval(-60), now: now), "NOW")
    }

    func testCountdownHoursUnderADay() {
        let now = Date()
        XCTAssertEqual(CaseTabCopy.countdown(to: now.addingTimeInterval(3600 * 6), now: now), "T-6H")
    }

    func testCountdownRoundsUpPartialHour() {
        let now = Date()
        // 5h10m out rounds up to T-6H, not truncates to T-5H.
        XCTAssertEqual(CaseTabCopy.countdown(to: now.addingTimeInterval(3600 * 5 + 600), now: now), "T-6H")
    }

    func testCountdownDaysAtOrOverADay() {
        let now = Date()
        XCTAssertEqual(CaseTabCopy.countdown(to: now.addingTimeInterval(3600 * 24 * 3), now: now), "T-3D")
    }

    // MARK: - CaseTabCopy.pendingOfferLabel

    func testPendingOfferLabelInterviewerOffersToInterviewYou() {
        // fromRole "interviewer" — they'd interview you (you'd be candidate).
        XCTAssertEqual(
            CaseTabCopy.pendingOfferLabel(fromName: "T. Becker", fromRole: "interviewer"),
            "T. Becker offers to interview you"
        )
    }

    func testPendingOfferLabelCandidateAsksYouToInterview() {
        // fromRole "candidate" — they'd be candidate; asking you to interview them.
        XCTAssertEqual(
            CaseTabCopy.pendingOfferLabel(fromName: "S. Park", fromRole: "candidate"),
            "S. Park asks you to interview"
        )
    }

    // MARK: - CaseTabGateSteering

    func testGateSteeringAppendsRecapRouteAndClearsGate() {
        var path: [AppRoute] = []
        var cleared = false

        CaseTabGateSteering.steer(sessionID: 555, casePath: &path) { cleared = true }

        XCTAssertEqual(path, [.recap(555)])
        XCTAssertTrue(cleared)
    }

    func testGateSteeringAppendsOntoExistingPath() {
        var path: [AppRoute] = [.recap(1)]
        var cleared = false

        CaseTabGateSteering.steer(sessionID: 2, casePath: &path) { cleared = true }

        XCTAssertEqual(path, [.recap(1), .recap(2)])
        XCTAssertTrue(cleared)
    }

    func testGateSteeringNoOpWhenSessionIDNil() {
        var path: [AppRoute] = []

        CaseTabGateSteering.steer(sessionID: nil, casePath: &path) {
            XCTFail("clearGate should not run when there is nothing to steer")
        }

        XCTAssertTrue(path.isEmpty)
    }

    // MARK: - CasePrefillSteering (F4→F3 case-prefill)

    func testPrefillSteeringNilWhenNothingSet() {
        XCTAssertNil(CasePrefillSteering.target(getCasedID: nil, someoneID: nil, someoneTitle: nil))
    }

    func testPrefillSteeringOpenCaseGoesToGetCased() {
        XCTAssertEqual(
            CasePrefillSteering.target(getCasedID: 6, someoneID: nil, someoneTitle: nil),
            .getCased(6)
        )
    }

    func testPrefillSteeringDoneCaseGoesToCaseSomeoneWithTitle() {
        XCTAssertEqual(
            CasePrefillSteering.target(getCasedID: nil, someoneID: 6, someoneTitle: "Ski resort"),
            .caseSomeone(id: 6, title: "Ski resort")
        )
    }

    func testPrefillSteeringCaseSomeoneTakesPriority() {
        // Defensive: the two fields are mutually exclusive by construction, but
        // if both were somehow set, caseSomeone wins.
        XCTAssertEqual(
            CasePrefillSteering.target(getCasedID: 7, someoneID: 6, someoneTitle: nil),
            .caseSomeone(id: 6, title: nil)
        )
    }

    // MARK: - CaseSheet

    func testCaseSheetTitlesAreVerbatim() {
        XCTAssertEqual(CaseSheet.getCased.title, "Get cased now")
        XCTAssertEqual(CaseSheet.caseSomeone.title, "Case someone")
        XCTAssertEqual(CaseSheet.schedule.title, "Schedule")
    }

    func testCaseSheetIdentifiableIdentityIsCaseItself() {
        XCTAssertEqual(CaseSheet.getCased.id, .getCased)
        XCTAssertNotEqual(CaseSheet.getCased.id, .caseSomeone)
    }

    // MARK: - CaseTabLayout (F3 T6 — tablet vs phone size-class selection)

    func testLayoutIsTabletOnlyOnRegularSizeClass() {
        XCTAssertTrue(CaseTabLayout.isTablet(.regular))
        XCTAssertFalse(CaseTabLayout.isTablet(.compact))
        XCTAssertFalse(CaseTabLayout.isTablet(nil))
    }
}
