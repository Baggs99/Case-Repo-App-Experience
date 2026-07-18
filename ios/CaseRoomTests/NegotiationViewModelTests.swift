/*
 * Purpose: Unit tests for the F5 negotiation logic + view model — turn logic
 *          (roundUsed/whoseTurn → stage), counter-once gating, the candidate's
 *          "THEY KEPT THEIR PICK" resolution detection, the candidate-accepts-
 *          only-the-pick rule, and the propose/accept actions over a stubbed
 *          SessionFlowService (no network).
 * Inputs: none (in-memory stub flow service + hand-built NegotiationView values).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubSessionFlowService: SessionFlowService {
    var negotiationResult: Result<NegotiationView, Error>
    var proposeResult: Result<NegotiationView, Error>
    var acceptResult: Result<SessionDetail, Error>

    private(set) var recordedProposeCaseIds: [Int] = []
    private(set) var recordedAcceptCaseIds: [Int] = []

    init(view: NegotiationView) {
        self.negotiationResult = .success(view)
        self.proposeResult = .success(view)
        self.acceptResult = .success(SessionDetail(
            id: view.sessionId, interviewerId: 1, candidateId: 2, caseId: 91,
            state: "lobby", mode: "remote", consentInterviewer: false, consentCandidate: false,
            scheduledAt: nil, startedAt: nil, endedAt: nil,
            interviewerName: "I", candidateName: "C", caseTitle: "T", yourRole: view.yourRole))
    }

    func negotiation(id: Int) async throws -> NegotiationView { try negotiationResult.get() }
    func proposeCase(id: Int, caseId: Int) async throws -> NegotiationView {
        recordedProposeCaseIds.append(caseId)
        return try proposeResult.get()
    }
    func acceptCase(id: Int, caseId: Int) async throws -> SessionDetail {
        recordedAcceptCaseIds.append(caseId)
        return try acceptResult.get()
    }
    // Unused by NegotiationViewModel.
    func swap(id: Int) async throws -> SwapInitiated { fatalError("not used") }
    func swapAccept(id: Int) async throws -> SwapAccepted { fatalError("not used") }
    func recaps() async throws -> [RecapListItem] { fatalError("not used") }
    func recapViewed(id: Int) async throws -> RecapViewedResult { fatalError("not used") }
    func recapClose(id: Int, caseRating: Int, thumbs: Bool?) async throws -> RecapCloseResult { fatalError("not used") }
    func feedbackReport(id: Int) async throws -> FeedbackReport { fatalError("not used") }
}

final class NegotiationViewModelTests: XCTestCase {

    private let pick = NegotiatedCaseBrief(caseId: 91, title: "Nordic carrier", caseType: "Market entry", difficulty: "D4")
    private let counter = NegotiatedCaseBrief(caseId: 8, title: "EV charging", caseType: "Market sizing", difficulty: "D3")

    private func makeView(
        role: String = "candidate", whoseTurn: String? = nil, roundUsed: Int = 0,
        pick: NegotiatedCaseBrief? = nil, counter: NegotiatedCaseBrief? = nil,
        sources: PickSources? = nil, state: String = "negotiating"
    ) -> NegotiationView {
        NegotiationView(
            sessionId: 1, sessionState: state, yourRole: role, whoseTurn: whoseTurn,
            roundUsed: roundUsed, currentPick: pick, candidateCounter: counter,
            candidateRequestedCase: nil, pickSources: sources)
    }

    // MARK: - Candidate turn logic (roundUsed / whoseTurn → stage)

    func testWaitingForPickWhenInterviewerHasNotPicked() {
        let view = makeView(whoseTurn: "interviewer", roundUsed: 0)
        XCTAssertEqual(NegotiationLogic.candidateStage(view: view, resolution: nil), .waitingForPick)
        XCTAssertFalse(NegotiationLogic.candidateCanDecide(view))
    }

    func testDecideWhenPickShownAndCandidatesTurn() {
        let view = makeView(whoseTurn: "candidate", roundUsed: 1, pick: pick)
        XCTAssertEqual(NegotiationLogic.candidateStage(view: view, resolution: nil), .decide(pick))
        XCTAssertTrue(NegotiationLogic.candidateCanDecide(view))
    }

    func testCounterSentGatesFurtherCounters() {
        // Counter used (round 2) → interviewer's turn → candidate can no longer act.
        let view = makeView(whoseTurn: "interviewer", roundUsed: 2, pick: pick, counter: counter)
        XCTAssertEqual(NegotiationLogic.candidateStage(view: view, resolution: nil), .counterSent)
        XCTAssertFalse(NegotiationLogic.candidateCanDecide(view))
    }

    // MARK: - "THEY KEPT THEIR PICK" resolution detection

    func testKeptPickWhenStampedEqualsPickOverCounter() {
        let view = makeView(roundUsed: 2, pick: pick, counter: counter, state: "lobby")
        let resolution = NegotiationLogic.resolution(view: view, stampedCaseId: pick.caseId)
        XCTAssertEqual(resolution, .keptPick)
        XCTAssertEqual(NegotiationLogic.candidateStage(view: view, resolution: resolution), .keptPick(pick))
    }

    func testTookCounterWhenStampedEqualsCounter() {
        let view = makeView(roundUsed: 2, pick: pick, counter: counter, state: "lobby")
        let resolution = NegotiationLogic.resolution(view: view, stampedCaseId: counter.caseId)
        XCTAssertEqual(resolution, .tookCounter)
        XCTAssertEqual(NegotiationLogic.candidateStage(view: view, resolution: resolution), .tookCounter(counter))
    }

    func testNoResolutionWhenNoCounterEverMade() {
        // Candidate accepted the pick with no counter — a plain accept, not a
        // "kept pick" moment.
        let view = makeView(roundUsed: 1, pick: pick, counter: nil, state: "lobby")
        XCTAssertNil(NegotiationLogic.resolution(view: view, stampedCaseId: pick.caseId))
    }

    func testNoResolutionWhileUnstamped() {
        let view = makeView(roundUsed: 2, pick: pick, counter: counter)
        XCTAssertNil(NegotiationLogic.resolution(view: view, stampedCaseId: nil))
    }

    // MARK: - Interviewer stages

    func testInterviewerChoosePickWhenNoPick() {
        let sources = PickSources(recommendedForCandidate: [], interviewerDoneSet: [], libraryAllowed: true)
        let view = makeView(role: "interviewer", whoseTurn: "interviewer", roundUsed: 0, sources: sources)
        XCTAssertEqual(NegotiationLogic.interviewerStage(view: view), .choosePick(sources))
    }

    func testInterviewerAwaitingCandidateAfterPick() {
        let view = makeView(role: "interviewer", whoseTurn: "candidate", roundUsed: 1, pick: pick)
        XCTAssertEqual(NegotiationLogic.interviewerStage(view: view), .awaitingCandidate(pick))
    }

    func testInterviewerResolveAfterCounter() {
        let view = makeView(role: "interviewer", whoseTurn: "interviewer", roundUsed: 2, pick: pick, counter: counter)
        XCTAssertEqual(NegotiationLogic.interviewerStage(view: view), .resolve(pick: pick, counter: counter))
    }

    // MARK: - VM: candidate-accepts-only-the-pick rule

    @MainActor
    func testCandidateAcceptUsesInterviewerPickId() async {
        let view = makeView(whoseTurn: "candidate", roundUsed: 1, pick: pick)
        let service = StubSessionFlowService(view: view)
        let vm = NegotiationViewModel(sessionId: 1, service: service)
        await vm.refresh(stampedCaseId: nil)

        XCTAssertEqual(vm.candidateAcceptCaseId, pick.caseId)

        _ = await vm.accept(caseId: vm.candidateAcceptCaseId ?? -1)
        XCTAssertEqual(service.recordedAcceptCaseIds, [pick.caseId])
    }

    // MARK: - VM: propose / accept / resolution wiring

    @MainActor
    func testProposeUpdatesViewFromResponse() async {
        let initial = makeView(whoseTurn: "candidate", roundUsed: 1, pick: pick)
        let service = StubSessionFlowService(view: initial)
        let countered = makeView(whoseTurn: "interviewer", roundUsed: 2, pick: pick, counter: counter)
        service.proposeResult = .success(countered)
        let vm = NegotiationViewModel(sessionId: 1, service: service)
        await vm.refresh(stampedCaseId: nil)

        await vm.propose(caseId: counter.caseId)

        XCTAssertEqual(service.recordedProposeCaseIds, [counter.caseId])
        XCTAssertEqual(vm.view?.candidateCounter, counter)
        XCTAssertEqual(vm.candidateStage, .counterSent)
    }

    @MainActor
    func testAcceptReturnsTrueOnStamp() async {
        let view = makeView(role: "interviewer", whoseTurn: "interviewer", roundUsed: 2, pick: pick, counter: counter)
        let service = StubSessionFlowService(view: view)
        let vm = NegotiationViewModel(sessionId: 1, service: service)
        await vm.refresh(stampedCaseId: nil)

        let stamped = await vm.accept(caseId: pick.caseId)
        XCTAssertTrue(stamped)
        XCTAssertEqual(service.recordedAcceptCaseIds, [pick.caseId])
    }

    @MainActor
    func testCandidateRefreshDetectsKeptPickResolution() async {
        // Candidate had a counter outstanding; a peer accept stamps the pick.
        let resolved = makeView(whoseTurn: nil, roundUsed: 2, pick: pick, counter: counter, state: "lobby")
        let service = StubSessionFlowService(view: resolved)
        let vm = NegotiationViewModel(sessionId: 1, service: service)

        await vm.refresh(stampedCaseId: pick.caseId)

        XCTAssertEqual(vm.resolution, .keptPick)
        XCTAssertEqual(vm.candidateStage, .keptPick(pick))
    }

    @MainActor
    func testInterviewerNeverGetsCandidateResolution() async {
        let resolved = makeView(role: "interviewer", whoseTurn: nil, roundUsed: 2, pick: pick, counter: counter, state: "lobby")
        let service = StubSessionFlowService(view: resolved)
        let vm = NegotiationViewModel(sessionId: 1, service: service)

        await vm.refresh(stampedCaseId: pick.caseId)

        XCTAssertNil(vm.resolution)
    }
}
