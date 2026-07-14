/*
 * Purpose: Unit tests for SessionViewModel — stubbed SessionService +
 *          SignalingChannel proving the lobby state machine (knock/admit/
 *          deny/consent/go-live) without a real network call or WebSocket
 *          (the live socket is exercised in Task 15).
 * Inputs: none (in-memory stub service/signaling).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubSessionService: SessionService {
    var sessionDetailResult: Result<SessionDetail, Error>
    var setConsentResult: Result<SessionDetail, Error>
    var transitionResult: Result<SessionDetail, Error>

    private(set) var recordedConsentIds: [Int] = []
    private(set) var recordedConsentValues: [Bool] = []
    private(set) var recordedTransitionIds: [Int] = []
    private(set) var recordedTransitionTargets: [String] = []

    init(detail: SessionDetail) {
        self.sessionDetailResult = .success(detail)
        self.setConsentResult = .success(detail)
        self.transitionResult = .success(detail)
    }

    func sessionDetail(id: Int) async throws -> SessionDetail {
        try sessionDetailResult.get()
    }

    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail {
        recordedConsentIds.append(id)
        recordedConsentValues.append(consent)
        return try setConsentResult.get()
    }

    func transition(id: Int, target: String) async throws -> SessionDetail {
        recordedTransitionIds.append(id)
        recordedTransitionTargets.append(target)
        return try transitionResult.get()
    }

    // Unused by SessionViewModel — required by the SessionService protocol.
    func rubric(id: Int) async throws -> RubricState { fatalError("not used") }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { fatalError("not used") }
    func reveal(id: Int, exhibitId: Int) async throws { fatalError("not used") }
    func exhibits(id: Int) async throws -> [ExhibitMeta] { fatalError("not used") }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { fatalError("not used") }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { fatalError("not used") }
    func completeRecording(id: Int) async throws { fatalError("not used") }
    func finalize(id: Int, grade: Double?) async throws { fatalError("not used") }
}

final class StubSignalingChannel: SignalingChannel {
    private var continuation: AsyncStream<SignalMessage>.Continuation?
    private(set) var recordedSentData: [Data] = []
    private(set) var connectedSessionIds: [Int] = []
    private(set) var disconnectCallCount = 0

    func connect(sessionId: Int) async -> AsyncStream<SignalMessage> {
        connectedSessionIds.append(sessionId)
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func send(_ data: Data) async {
        recordedSentData.append(data)
    }

    func disconnect() async {
        disconnectCallCount += 1
        continuation?.finish()
    }

    /// Test-only helper — scripts an inbound message onto the stream handed
    /// back from connect(sessionId:).
    func push(_ message: SignalMessage) {
        continuation?.yield(message)
    }
}

final class SessionViewModelTests: XCTestCase {
    private func makeDetail(
        state: String = "lobby", yourRole: String? = "candidate",
        consentInterviewer: Bool = false, consentCandidate: Bool = false
    ) -> SessionDetail {
        SessionDetail(
            id: 42, interviewerId: 1, candidateId: 2, caseId: 5,
            state: state, consentInterviewer: consentInterviewer, consentCandidate: consentCandidate,
            scheduledAt: nil, startedAt: nil, endedAt: nil,
            interviewerName: "Alice Dev", candidateName: "Bob Dev",
            caseTitle: "Widget Co", yourRole: yourRole
        )
    }

    private func decodeType(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict["type"] as? String
    }

    // Gives the VM's inbound-message consumer task a chance to run after a
    // scripted push — it's a separate unstructured Task, not on the calling
    // continuation.
    private func flush() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    // MARK: - knock (candidate)

    func testCandidateKnockSendsKnockOutbound() async {
        let service = StubSessionService(detail: makeDetail(yourRole: "candidate"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.knock()

        XCTAssertEqual(signaling.recordedSentData.count, 1)
        XCTAssertEqual(decodeType(signaling.recordedSentData[0]), "knock")
    }

    // MARK: - inbound knock (interviewer)

    func testInterviewerReceivingKnockSetsPeerKnocked() async {
        let service = StubSessionService(detail: makeDetail(yourRole: "interviewer"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        signaling.push(.knock(displayName: "Dan"))
        await flush()

        let peerKnocked = await viewModel.peerKnocked
        let knockerName = await viewModel.knockerName
        XCTAssertTrue(peerKnocked)
        XCTAssertEqual(knockerName, "Dan")
    }

    // MARK: - admit (interviewer)

    func testInterviewerAdmitSendsAdmitOutbound() async {
        let service = StubSessionService(detail: makeDetail(yourRole: "interviewer"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.admit()

        XCTAssertEqual(signaling.recordedSentData.count, 1)
        XCTAssertEqual(decodeType(signaling.recordedSentData[0]), "admit")
    }

    // MARK: - toggleConsent

    func testToggleConsentCallsSetConsentAndFlipsLocalFlagFromReturnedSession() async {
        let service = StubSessionService(detail: makeDetail(yourRole: "candidate", consentCandidate: false))
        service.setConsentResult = .success(makeDetail(yourRole: "candidate", consentCandidate: true))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()
        let before = await viewModel.consentCandidate
        XCTAssertFalse(before)

        await viewModel.toggleConsent()

        XCTAssertEqual(service.recordedConsentIds, [42])
        XCTAssertEqual(service.recordedConsentValues, [true])
        let after = await viewModel.consentCandidate
        XCTAssertTrue(after)
    }

    // MARK: - goLive

    func testGoLiveDoesNotTransitionWhenOnlyOneConsentIsTrue() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", consentInterviewer: true, consentCandidate: false)
        )
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.goLive()

        XCTAssertTrue(service.recordedTransitionIds.isEmpty)
    }

    func testGoLiveDoesNotTransitionWhenNeitherConsentIsTrue() async {
        let service = StubSessionService(detail: makeDetail(yourRole: "interviewer"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.goLive()

        XCTAssertTrue(service.recordedTransitionIds.isEmpty)
    }

    func testGoLiveTransitionsWhenBothConsentAreTrue() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.goLive()

        XCTAssertEqual(service.recordedTransitionIds, [42])
        XCTAssertEqual(service.recordedTransitionTargets, ["live"])
        let state = await viewModel.state
        XCTAssertEqual(state, "live")
    }
}
