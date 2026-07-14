/*
 * Purpose: Unit tests for SessionViewModel — stubbed SessionService +
 *          SignalingChannel + RoomRecording + RecordingUploading proving the
 *          lobby state machine (knock/admit/deny/consent/go-live), finalize,
 *          the interviewer recorder lifecycle, and reveal routing to the
 *          candidate's ExhibitsViewModel, without a real network call,
 *          WebSocket, or microphone (the live socket + real mic are
 *          exercised in Task 15).
 * Inputs: none (in-memory stub service/signaling/recorder/uploader).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubSessionService: SessionService {
    var sessionDetailResult: Result<SessionDetail, Error>
    var setConsentResult: Result<SessionDetail, Error>
    var transitionResult: Result<SessionDetail, Error>
    var finalizeResult: Result<Finalized, Error> = .success(Finalized(grade: 0, finalizedAt: Date()))

    private(set) var recordedConsentIds: [Int] = []
    private(set) var recordedConsentValues: [Bool] = []
    private(set) var recordedTransitionIds: [Int] = []
    private(set) var recordedTransitionTargets: [String] = []
    private(set) var recordedFinalizeIds: [Int] = []
    private(set) var recordedFinalizeGrades: [Double?] = []

    init(detail: SessionDetail) {
        self.sessionDetailResult = .success(detail)
        self.setConsentResult = .success(detail)
        self.transitionResult = .success(detail)
    }

    func sessionDetail(id: Int) async throws -> SessionDetail {
        try sessionDetailResult.get()
    }

    func joinConfig(id: Int) async throws -> JoinConfig { fatalError("not used") }

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

    func finalize(id: Int, grade: Double?) async throws -> Finalized {
        recordedFinalizeIds.append(id)
        recordedFinalizeGrades.append(grade)
        return try finalizeResult.get()
    }

    // Unused by SessionViewModel — required by the SessionService protocol.
    func rubric(id: Int) async throws -> RubricState { fatalError("not used") }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { fatalError("not used") }
    func reveal(id: Int, exhibitId: Int) async throws { fatalError("not used") }
    func exhibits(id: Int) async throws -> [ExhibitMeta] { fatalError("not used") }
    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data { fatalError("not used") }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { fatalError("not used") }
    func completeRecording(id: Int) async throws { fatalError("not used") }
}

final class StubRoomRecording: RoomRecording {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var stopURL: URL = URL(fileURLWithPath: "/tmp/stub-recording.m4a")

    func start() async throws {
        startCallCount += 1
    }

    func stop() -> URL {
        stopCallCount += 1
        return stopURL
    }
}

final class StubRecordingUploader: RecordingUploading {
    private(set) var recordedFileURLs: [URL] = []
    private(set) var recordedSessionIds: [Int] = []

    func upload(fileURL: URL, sessionId: Int, service: SessionService) async throws {
        recordedFileURLs.append(fileURL)
        recordedSessionIds.append(sessionId)
    }
}

final class StubExhibitReceiver: ExhibitRevealReceiving {
    private(set) var recordedExhibitIds: [Int] = []
    private(set) var recordedKeys: [String] = []

    func handleReveal(exhibitId: Int, keyB64: String) {
        recordedExhibitIds.append(exhibitId)
        recordedKeys.append(keyB64)
    }
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
            state: state, mode: "remote", consentInterviewer: consentInterviewer, consentCandidate: consentCandidate,
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

    // MARK: - finalize

    func testFinalizeCallsServiceOnlyInDebriefState() async {
        let service = StubSessionService(
            detail: makeDetail(state: "live", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.finalize(grade: 88.5)

        XCTAssertTrue(service.recordedFinalizeIds.isEmpty)
        let finalized = await viewModel.finalized
        XCTAssertFalse(finalized)
    }

    func testFinalizeCallsServiceAndMarksFinalizedInDebriefState() async {
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        service.finalizeResult = .success(Finalized(grade: 88.5, finalizedAt: Date()))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.finalize(grade: 88.5)

        XCTAssertEqual(service.recordedFinalizeIds, [42])
        XCTAssertEqual(service.recordedFinalizeGrades, [88.5])
        let finalized = await viewModel.finalized
        let releasedGrade = await viewModel.releasedGrade
        XCTAssertTrue(finalized)
        XCTAssertEqual(releasedGrade, 88.5)
    }

    // Proves the released grade always comes from the server's response,
    // not the local override param — the common no-override path (nil)
    // must not leave releasedGrade nil (which the DebriefView renders as
    // "Pending").
    func testFinalizeWithNilGradeUsesServerReleasedGrade() async {
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        service.finalizeResult = .success(Finalized(grade: 3.6, finalizedAt: Date()))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.finalize(grade: nil)

        let releasedGrade = await viewModel.releasedGrade
        XCTAssertEqual(releasedGrade, 3.6)
    }

    // A candidate must not be able to finalize, even in "debrief".
    func testFinalizeDoesNotCallServiceForCandidateRole() async {
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "candidate", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()

        await viewModel.finalize(grade: 90)

        XCTAssertTrue(service.recordedFinalizeIds.isEmpty)
        let finalized = await viewModel.finalized
        XCTAssertFalse(finalized)
    }

    // MARK: - interviewer recorder lifecycle

    func testInterviewerEnteringLiveStartsRecorder() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let recorder = StubRoomRecording()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, recorder: recorder
        )
        await viewModel.load()

        await viewModel.goLive()

        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func testCandidateEnteringLiveNeverStartsRecorder() async {
        let service = StubSessionService(
            detail: makeDetail(state: "live", yourRole: "candidate", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let recorder = StubRoomRecording()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, recorder: recorder
        )

        await viewModel.load()

        XCTAssertEqual(recorder.startCallCount, 0)
    }

    func testFinalizeStopsRecorderAndUploadsForInterviewer() async {
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let recorder = StubRoomRecording()
        let uploader = StubRecordingUploader()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, recorder: recorder, uploader: uploader
        )
        await viewModel.load()

        await viewModel.finalize(grade: 90)

        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(uploader.recordedFileURLs, [recorder.stopURL])
        XCTAssertEqual(uploader.recordedSessionIds, [42])
    }

    func testFinalizeUploadFailureDoesNotBlockFinalize() async {
        struct UploadError: Error {}
        final class FailingUploader: RecordingUploading {
            func upload(fileURL: URL, sessionId: Int, service: SessionService) async throws {
                throw UploadError()
            }
        }
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let recorder = StubRoomRecording()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, recorder: recorder, uploader: FailingUploader()
        )
        await viewModel.load()

        await viewModel.finalize(grade: 90)

        let finalized = await viewModel.finalized
        XCTAssertTrue(finalized)
    }

    // MARK: - reveal routing

    func testInboundRevealForwardsToExhibitReceiver() async {
        let service = StubSessionService(detail: makeDetail(state: "live", yourRole: "candidate"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        let receiver = await StubExhibitReceiver()
        await MainActor.run { viewModel.exhibitReceiver = receiver }
        await viewModel.load()

        signaling.push(.reveal(exhibitId: 5, keyB64: "K"))
        await flush()

        let recordedExhibitIds = await receiver.recordedExhibitIds
        let recordedKeys = await receiver.recordedKeys
        XCTAssertEqual(recordedExhibitIds, [5])
        XCTAssertEqual(recordedKeys, ["K"])
    }

    // MARK: - session-update routing

    // A peer-driven state change (e.g. the interviewer going live) arrives as
    // a bare "session-update" ping with no payload — the VM must re-fetch the
    // session detail and re-apply it so this client's state machine advances.
    func testInboundSessionUpdateRefetchesAndAppliesNewState() async {
        let service = StubSessionService(detail: makeDetail(state: "lobby", yourRole: "candidate"))
        let signaling = StubSignalingChannel()
        let viewModel = await SessionViewModel(sessionId: 42, service: service, signaling: signaling)
        await viewModel.load()
        let stateBefore = await viewModel.state
        XCTAssertEqual(stateBefore, "lobby")

        service.sessionDetailResult = .success(makeDetail(state: "debrief", yourRole: "candidate"))
        signaling.push(.sessionUpdate)
        await flush()

        let state = await viewModel.state
        XCTAssertEqual(state, "debrief")
    }
}
