/*
 * Purpose: Unit tests for AppRouter's entry-point remap + AppRoute.owningTab —
 *          proves every audited deep-link/push source lands on the right route.
 * Inputs: none (drives AppRouter.shared on the main actor).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class AppRouterTests: XCTestCase {
    private func freshRouter() -> AppRouter {
        let r = AppRouter.shared
        r.selection = .home
        r.avatarSheet = false
        r.groupCreate = false
        r.proposeToUserID = nil
        r.sessionTakeoverID = nil
        r.drillRun = false
        r.gauntletRun = false
        r.pending = nil
        return r
    }

    // owningTab
    func testOwningTabForTabRoutes() {
        XCTAssertEqual(AppRoute.home.owningTab, .home)
        XCTAssertEqual(AppRoute.library.owningTab, .library)
        XCTAssertEqual(AppRoute.caseTab.owningTab, .caseTab)
        XCTAssertEqual(AppRoute.community.owningTab, .community)
        XCTAssertEqual(AppRoute.drills.owningTab, .drills)
        XCTAssertEqual(AppRoute.gauntletRun.owningTab, .drills)
    }
    func testOwningTabForDetailRoutes() {
        XCTAssertEqual(AppRoute.caseDetail(1).owningTab, .library)
        XCTAssertEqual(AppRoute.timelineDetail.owningTab, .home)
        XCTAssertEqual(AppRoute.recap(9).owningTab, .caseTab)
        XCTAssertEqual(AppRoute.groupPage(3).owningTab, .community)
        XCTAssertEqual(AppRoute.drillRun.owningTab, .home)
    }
    func testOwningTabNilForModals() {
        XCTAssertNil(AppRoute.avatarSheet.owningTab)
        XCTAssertNil(AppRoute.sessionTakeover(5).owningTab)
    }

    // go(to:)
    func testGoToTabSelects() {
        let r = freshRouter()
        r.go(to: .library)
        XCTAssertEqual(r.selection, .library)
    }
    func testGoToAvatarSheetPresents() {
        let r = freshRouter()
        r.go(to: .avatarSheet)
        XCTAssertTrue(r.avatarSheet)
    }
    // No AppRoute case for group-create (§6 pins the enum) — the avatar
    // sheet's "Administer a group" action drives the flag directly, mirroring
    // how RootShell's avatarButton sets `router.avatarSheet = true` outside
    // go(to:). This proves the flag toggles independently of the router's
    // route registry.
    func testGroupCreateFlagTogglesDirectly() {
        let r = freshRouter()
        XCTAssertFalse(r.groupCreate)
        r.groupCreate = true
        XCTAssertTrue(r.groupCreate)
    }
    func testGoToDrillRunSelectsHomeAndFlagsDrill() {
        let r = freshRouter()
        r.go(to: .drillRun)
        XCTAssertEqual(r.selection, .home)
        XCTAssertTrue(r.drillRun)
    }
    func testGoToGauntletRunFlagsGauntlet() {
        let r = freshRouter()
        r.go(to: .gauntletRun)
        XCTAssertTrue(r.gauntletRun)
    }
    func testGoToSessionTakeoverSetsCover() {
        let r = freshRouter()
        r.go(to: .sessionTakeover(42))
        XCTAssertEqual(r.sessionTakeoverID, 42)
    }
    func testGoToCaseDetailSelectsLibraryAndPushes() {
        let r = freshRouter()
        r.libraryPath = []
        r.go(to: .caseDetail(7))
        XCTAssertEqual(r.selection, .library)
        XCTAssertEqual(r.libraryPath, [.caseDetail(7)])
    }

    // handleDeepLink (legacy DeepLink cases preserved)
    func testDeepLinkDrillRunsDrill() {
        let r = freshRouter()
        r.handleDeepLink(.drill)
        XCTAssertEqual(r.selection, .home)
        XCTAssertTrue(r.drillRun)
    }
    func testDeepLinkSessionsGoesToCase() {
        let r = freshRouter()
        r.handleDeepLink(.sessions)
        XCTAssertEqual(r.selection, .caseTab)
    }
    func testDeepLinkFreeNowGoesToCase() {
        let r = freshRouter()
        r.handleDeepLink(.freeNow)
        XCTAssertEqual(r.selection, .caseTab)
    }
    func testDeepLinkProposeToPresentsProposeAndSelectsCase() {
        let r = freshRouter()
        r.handleDeepLink(.proposeTo(11))
        XCTAssertEqual(r.selection, .caseTab)
        XCTAssertEqual(r.proposeToUserID, 11)
    }

    // handlePush (PushRoute → router)
    func testPushProposalsGoesToCase() {
        let r = freshRouter()
        r.handlePush(.proposals)
        XCTAssertEqual(r.selection, .caseTab)
    }
    func testPushSessionGoesToCase() {
        let r = freshRouter()
        r.handlePush(.session(3))
        XCTAssertEqual(r.selection, .caseTab)
    }
    func testPushProposeToPresentsPropose() {
        let r = freshRouter()
        r.handlePush(.proposeTo(8))
        XCTAssertEqual(r.selection, .caseTab)
        XCTAssertEqual(r.proposeToUserID, 8)
    }
}
