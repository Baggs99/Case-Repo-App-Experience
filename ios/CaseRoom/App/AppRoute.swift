/*
 * Purpose: The canonical navigation-destination registry (contract §6) — every
 *          tab, detail page, and modal the app can navigate to. Distinct from
 *          DSTab (tab identity) and DeepLink (steering-source parsing).
 * Inputs: none.
 * Outputs: AppRoute, AppRoute.owningTab.
 * Run: consumed by AppRouter.go(to:) and later phases' navigation.
 */

import Foundation

// Contract §6 — later phases add cases ONLY via their brief.
enum AppRoute: Hashable {
    case home, library, caseTab, community, drills
    case avatarSheet
    case timelineDetail
    case caseDetail(Int)
    case recap(Int)
    case sessionTakeover(Int)
    case groupPage(Int)
    case drillRun

    /// The tab that owns this route's surface, or nil for routes presented
    /// modally / over the whole shell (avatar sheet, session takeover). Detail
    /// routes resolve to the tab whose NavigationStack hosts them.
    var owningTab: DSTab? {
        switch self {
        case .home, .timelineDetail, .drillRun: return .home
        case .library, .caseDetail: return .library
        case .caseTab, .recap: return .caseTab
        case .community, .groupPage: return .community
        case .drills: return .drills
        case .avatarSheet, .sessionTakeover: return nil
        }
    }
}
