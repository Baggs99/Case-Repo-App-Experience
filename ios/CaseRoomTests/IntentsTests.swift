/*
 * Purpose: Unit tests for the App Intents layer's pure parts — DeepLink URL /
 *          PushRoute mapping, NextSessionIntent dialog composition,
 *          ToggleFreeNowIntent's toggle decision, and entity mapping/queries.
 * Inputs: none (in-memory fixtures + injected entity catalog).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class IntentsTests: XCTestCase {

    // MARK: - DeepLink URL parsing

    func testRouteFromDrillURL() {
        XCTAssertEqual(DeepLink.route(from: URL(string: "caseroom://drill")!), .drill)
    }

    func testRouteFromSessionsURL() {
        XCTAssertEqual(DeepLink.route(from: URL(string: "caseroom://sessions")!), .sessions)
    }

    func testRouteFromFreeNowURL() {
        XCTAssertEqual(DeepLink.route(from: URL(string: "caseroom://freenow")!), .freeNow)
    }

    func testRouteFromUnknownHostIsNil() {
        XCTAssertNil(DeepLink.route(from: URL(string: "caseroom://mystery")!))
    }

    func testRouteFromWrongSchemeIsNil() {
        XCTAssertNil(DeepLink.route(from: URL(string: "https://drill")!))
    }

    // MARK: - PushRoute -> DeepLink mapping

    func testProposalsMapsToSessions() {
        XCTAssertEqual(DeepLink(.proposals), .sessions)
    }

    func testSessionMapsToSessions() {
        XCTAssertEqual(DeepLink(.session(7)), .sessions)
    }

    func testProposeToMapsToProposeTo() {
        XCTAssertEqual(DeepLink(.proposeTo(3)), .proposeTo(3))
    }

    // MARK: - NextSessionIntent.dialogText

    func testDialogTextWithNextSession() {
        let next = SessionSummary(
            id: 1, role: "candidate", otherUser: "Bob Dev", caseTitle: "Widget Co",
            scheduledAt: Date(timeIntervalSinceNow: 3600), state: nil, endedAt: nil, grade: nil
        )
        let stats = DashboardStats(
            sessionsFinalized: 0, streakWeeks: 0, nextSession: next,
            streakDays: nil, drillDoneToday: nil
        )
        let text = NextSessionIntent.dialogText(for: stats)
        XCTAssertTrue(text.hasPrefix("Next: Widget Co with Bob Dev,"))
        XCTAssertTrue(text.hasSuffix("."))
    }

    func testDialogTextWithNoSession() {
        let stats = DashboardStats(
            sessionsFinalized: 0, streakWeeks: 0, nextSession: nil,
            streakDays: nil, drillDoneToday: nil
        )
        XCTAssertEqual(
            NextSessionIntent.dialogText(for: stats),
            "Nothing scheduled. Say 'I'm free now' to find a partner."
        )
    }

    func testRunComposesDialogFromFetchedStats() async throws {
        let next = SessionSummary(
            id: 1, role: "candidate", otherUser: "Cara", caseTitle: "Acme",
            scheduledAt: Date(timeIntervalSinceNow: 7200), state: nil, endedAt: nil, grade: nil
        )
        let stats = DashboardStats(
            sessionsFinalized: 2, streakWeeks: 1, nextSession: next,
            streakDays: nil, drillDoneToday: nil
        )
        let text = await NextSessionIntent.run { stats }
        XCTAssertTrue(text.hasPrefix("Next: Acme with Cara,"))
    }

    func testRunSpeaksFailureDialogWhenFetchThrows() async {
        let text = await NextSessionIntent.run { throw TestCatalogError.boom }
        XCTAssertEqual(text, NextSessionIntent.failureDialogText)
        XCTAssertEqual(text, "Couldn't reach CaseRoom — open the app and try again.")
    }

    // MARK: - ToggleFreeNowIntent.nextAction

    func testNextActionWhenFreeGoesOffline() {
        let status = AvailabilityStatus(freeUntil: Date(timeIntervalSinceNow: 3600), others: [])
        XCTAssertEqual(ToggleFreeNowIntent.nextAction(current: status), .goOffline)
    }

    func testNextActionWhenNotFreeGoesFree() {
        let status = AvailabilityStatus(freeUntil: nil, others: [])
        XCTAssertEqual(ToggleFreeNowIntent.nextAction(current: status), .goFree)
    }

    // MARK: - CaseEntity mapping

    func testCaseEntityFromSummary() {
        let summary = CaseSummary(
            id: 42, caseTitle: "Widget Co Profitability", caseType: "profitability",
            difficulty: "medium", difficultyScore: 0.5, firm: nil, industry: nil,
            industryDisplay: nil, industryRaw: nil, pageCount: 12,
            sourceSchool: "HBS", sourceYear: 2024,
            avgRating: nil, runCount: nil, doneForYou: nil
        )
        let entity = CaseEntity(from: summary)
        XCTAssertEqual(entity.id, 42)
        XCTAssertEqual(entity.title, "Widget Co Profitability")
        XCTAssertEqual(entity.school, "HBS")
        XCTAssertEqual(entity.difficulty, "medium")
    }

    func testSessionEntityFromSummary() {
        let summary = SessionSummary(
            id: 5, role: "interviewer", otherUser: "Dana", caseTitle: "Beta Growth",
            scheduledAt: nil, state: nil, endedAt: nil, grade: nil
        )
        let entity = SessionEntity(from: summary)
        XCTAssertEqual(entity.id, 5)
        XCTAssertEqual(entity.caseTitle, "Beta Growth")
        XCTAssertEqual(entity.otherUser, "Dana")
    }

    func testProposalEntityFromProposal() {
        let proposal = Proposal(
            id: 9, fromName: "Eve", fromRole: "candidate", caseId: 3, caseTitle: "Gamma Ops",
            caseType: nil, difficulty: nil, message: nil, proposedTimes: [], createdAt: Date()
        )
        let entity = ProposalEntity(from: proposal)
        XCTAssertEqual(entity.id, 9)
        XCTAssertEqual(entity.caseTitle, "Gamma Ops")
        XCTAssertEqual(entity.fromName, "Eve")
    }

    // MARK: - CaseEntityQuery via injected catalog

    func testCaseEntityQueryEntitiesForIds() async throws {
        let query = CaseEntityQuery(catalog: FakeCatalog())
        let entities = try await query.entities(for: [42])
        XCTAssertEqual(entities.map(\.id), [42])
        XCTAssertEqual(entities.first?.title, "Detail Co")
    }

    func testCaseEntitySuggestedReturnsFirstFive() async throws {
        let query = CaseEntityQuery(catalog: FakeCatalog())
        let entities = try await query.suggestedEntities()
        XCTAssertEqual(entities.count, 5)
        XCTAssertEqual(entities.first?.id, 0)
    }

    func testCaseEntitySuggestedReturnsEmptyOnError() async throws {
        let query = CaseEntityQuery(catalog: FailingCatalog())
        let entities = try await query.suggestedEntities()
        XCTAssertTrue(entities.isEmpty)
    }

    func testSessionEntitySuggestedReturnsEmptyOnError() async throws {
        let query = SessionEntityQuery(catalog: FailingCatalog())
        let entities = try await query.suggestedEntities()
        XCTAssertTrue(entities.isEmpty)
    }

    func testProposalEntitySuggestedReturnsEmptyOnError() async throws {
        let query = ProposalEntityQuery(catalog: FailingCatalog())
        let entities = try await query.suggestedEntities()
        XCTAssertTrue(entities.isEmpty)
    }
}

// MARK: - Test doubles

private enum TestCatalogError: Error { case boom }

private struct FakeCatalog: EntityCatalog {
    func caseDetail(id: Int) async throws -> CaseDetail {
        CaseDetail(
            id: id, caseTitle: "Detail Co", caseType: nil, difficulty: "hard",
            difficultyScore: nil, firm: nil, industry: nil, industryDisplay: nil,
            industryRaw: nil, pageCount: nil, sourceSchool: "Wharton", sourceYear: nil,
            previewUrls: [], pdfUrl: "/x.pdf",
            avgRating: nil, runCount: nil, doneForYou: nil
        )
    }

    func cases() async throws -> [CaseSummary] {
        (0..<7).map { i in
            CaseSummary(
                id: i, caseTitle: "Case \(i)", caseType: nil, difficulty: nil,
                difficultyScore: nil, firm: nil, industry: nil, industryDisplay: nil,
                industryRaw: nil, pageCount: nil, sourceSchool: nil, sourceYear: nil,
                avgRating: nil, runCount: nil, doneForYou: nil
            )
        }
    }

    func sessions() async throws -> [SessionSummary] {
        (0..<7).map { i in
            SessionSummary(
                id: i, role: "candidate", otherUser: "U\(i)", caseTitle: "S\(i)",
                scheduledAt: nil, state: nil, endedAt: nil, grade: nil
            )
        }
    }

    func proposals() async throws -> [Proposal] {
        (0..<7).map { i in
            Proposal(
                id: i, fromName: "F\(i)", fromRole: "candidate", caseId: i, caseTitle: "P\(i)",
                caseType: nil, difficulty: nil, message: nil, proposedTimes: [], createdAt: Date()
            )
        }
    }
}

private struct FailingCatalog: EntityCatalog {
    func caseDetail(id: Int) async throws -> CaseDetail { throw TestCatalogError.boom }
    func cases() async throws -> [CaseSummary] { throw TestCatalogError.boom }
    func sessions() async throws -> [SessionSummary] { throw TestCatalogError.boom }
    func proposals() async throws -> [Proposal] { throw TestCatalogError.boom }
}
