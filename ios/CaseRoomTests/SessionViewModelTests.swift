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
    var joinConfigResult: Result<JoinConfig, Error>

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
        self.joinConfigResult = .success(JoinConfig(
            sessionId: detail.id, yourRole: detail.yourRole ?? "candidate", wsPath: "",
            iceServers: [ICEServer(urls: ["stun:stub.example"], username: nil, credential: nil)]
        ))
    }

    func sessionDetail(id: Int) async throws -> SessionDetail {
        try sessionDetailResult.get()
    }

    func joinConfig(id: Int) async throws -> JoinConfig {
        try joinConfigResult.get()
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

final class StubRemoteMedia: RemoteMediaControlling {
    private(set) var startCallCount = 0
    private(set) var startPoliteValues: [Bool] = []
    private(set) var startICEServers: [[ICEServer]] = []
    private(set) var handledMessages: [SignalMessage] = []
    private(set) var setVideoEnabledValues: [Bool] = []
    private(set) var setAudioEnabledValues: [Bool] = []
    private(set) var stopCallCount = 0
    var startError: Error?

    var onRemoteTrack: (@MainActor (MediaTrackHandle) -> Void)?
    var capture: MediaCapturing? { nil }

    func start(signaling: SignalingChannel, iceServers: [ICEServer], polite: Bool) async throws {
        startCallCount += 1
        startPoliteValues.append(polite)
        startICEServers.append(iceServers)
        if let startError { throw startError }
    }

    func handle(_ message: SignalMessage) async {
        handledMessages.append(message)
    }

    func setVideoEnabled(_ enabled: Bool) {
        setVideoEnabledValues.append(enabled)
    }

    func setAudioEnabled(_ enabled: Bool) {
        setAudioEnabledValues.append(enabled)
    }

    func stop() {
        stopCallCount += 1
    }
}

final class StubLiveActivityControlling: LiveActivityControlling {
    private(set) var startCallCount = 0
    private(set) var recordedStartSessionIds: [Int] = []
    private(set) var recordedInitialStates: [SessionActivityAttributes.ContentState] = []
    private(set) var endCallCount = 0

    func start(sessionId: Int, initial: SessionActivityAttributes.ContentState) async {
        startCallCount += 1
        recordedStartSessionIds.append(sessionId)
        recordedInitialStates.append(initial)
    }

    func end() async {
        endCallCount += 1
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

    // Unused by SessionViewModel — required by the SignalingChannel protocol.
    func sendSDP(_ description: SDP) {}
    func sendICE(_ candidate: ICECandidate?) {}

    /// Test-only helper — scripts an inbound message onto the stream handed
    /// back from connect(sessionId:).
    func push(_ message: SignalMessage) {
        continuation?.yield(message)
    }
}

final class SessionViewModelTests: XCTestCase {
    private func makeDetail(
        state: String = "lobby", yourRole: String? = "candidate", mode: String = "remote",
        consentInterviewer: Bool = false, consentCandidate: Bool = false
    ) -> SessionDetail {
        SessionDetail(
            id: 42, interviewerId: 1, candidateId: 2, caseId: 5,
            state: state, mode: mode, consentInterviewer: consentInterviewer, consentCandidate: consentCandidate,
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

    // MARK: - remote media (Task 8)

    func testInterviewerRemoteModeLiveTransitionStartsMediaImpolite() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )
        await viewModel.load()

        await viewModel.goLive()

        let startCallCount = await media.startCallCount
        let startPoliteValues = await media.startPoliteValues
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(startPoliteValues, [false])
    }

    func testCandidateRemoteModeLiveTransitionStartsMediaPolite() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "candidate", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "candidate", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )
        await viewModel.load()

        await viewModel.goLive()

        let startCallCount = await media.startCallCount
        let startPoliteValues = await media.startPoliteValues
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(startPoliteValues, [true])
    }

    func testInPersonModeLiveTransitionDoesNotStartMedia() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", mode: "in_person", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", mode: "in_person", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )
        await viewModel.load()

        await viewModel.goLive()

        let startCallCount = await media.startCallCount
        XCTAssertEqual(startCallCount, 0)
    }

    func testToggleVideoTogglesMediaAndMediaCreatedOnlyOnce() async {
        let service = StubSessionService(
            detail: makeDetail(state: "live", yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )
        await viewModel.load()
        var startCallCount = await media.startCallCount
        XCTAssertEqual(startCallCount, 1)

        // A subsequent session-update while already live must not re-create
        // or re-start media (the mediaStarted guard holds).
        signaling.push(.sessionUpdate)
        await flush()
        startCallCount = await media.startCallCount
        XCTAssertEqual(startCallCount, 1)

        await viewModel.toggleVideo()

        let setVideoEnabledValues = await media.setVideoEnabledValues
        XCTAssertEqual(setVideoEnabledValues, [false])
        let videoEnabled = await viewModel.videoEnabled
        XCTAssertFalse(videoEnabled)
    }

    func testInboundSDPAndICEAfterStartForwardToMediaHandle() async {
        let service = StubSessionService(
            detail: makeDetail(yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )
        await viewModel.load()
        await viewModel.goLive()

        let sdp = SDP(type: "offer", sdp: "v=0")
        signaling.push(.sdp(description: sdp))
        signaling.push(.ice(candidate: nil))
        await flush()

        let handledMessages = await media.handledMessages
        XCTAssertEqual(handledMessages, [.sdp(description: sdp), .ice(candidate: nil)])
    }

    // A failed media start must surface as mediaStartError (not the generic
    // errorMessage) and retryStartMedia() must reset the mediaStarted guard
    // so it actually re-invokes media.start(), not silently no-op.
    func testMediaStartFailureSetsErrorAndRetryClearsItAndReattemptsStart() async {
        struct StubStartError: Error {}
        let service = StubSessionService(
            detail: makeDetail(state: "live", yourRole: "interviewer", mode: "remote", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let media = await StubRemoteMedia()
        await MainActor.run { media.startError = StubStartError() }
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, makeRemoteMedia: { media }
        )

        await viewModel.load()

        var mediaStartError = await viewModel.mediaStartError
        XCTAssertNotNil(mediaStartError)
        var startCallCount = await media.startCallCount
        XCTAssertEqual(startCallCount, 1)

        await MainActor.run { media.startError = nil }
        await viewModel.retryStartMedia()

        mediaStartError = await viewModel.mediaStartError
        XCTAssertNil(mediaStartError)
        startCallCount = await media.startCallCount
        XCTAssertEqual(startCallCount, 2)
    }

    // MARK: - Live Activity (Task 10)

    func testEnteringLobbyStartsLiveActivityOnceWithInitialContentState() async {
        let service = StubSessionService(detail: makeDetail(state: "lobby", yourRole: "candidate"))
        let signaling = StubSignalingChannel()
        let liveActivity = await StubLiveActivityControlling()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, liveActivity: liveActivity
        )

        await viewModel.load()

        let startCallCount = await liveActivity.startCallCount
        let recordedSessionIds = await liveActivity.recordedStartSessionIds
        let recordedInitialStates = await liveActivity.recordedInitialStates
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(recordedSessionIds, [42])
        XCTAssertEqual(recordedInitialStates.first?.state, "lobby")
        XCTAssertEqual(recordedInitialStates.first?.role, "candidate")
        XCTAssertEqual(recordedInitialStates.first?.counterpartName, "Alice Dev")
    }

    func testEnteringLiveStartsLiveActivityForInterviewer() async {
        let service = StubSessionService(
            detail: makeDetail(state: "live", yourRole: "interviewer", mode: "in_person")
        )
        let signaling = StubSignalingChannel()
        let liveActivity = await StubLiveActivityControlling()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, liveActivity: liveActivity
        )

        await viewModel.load()

        let startCallCount = await liveActivity.startCallCount
        let recordedInitialStates = await liveActivity.recordedInitialStates
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(recordedInitialStates.first?.role, "interviewer")
        XCTAssertEqual(recordedInitialStates.first?.counterpartName, "Bob Dev")
    }

    func testLobbyThenLiveTransitionStartsLiveActivityOnlyOnce() async {
        let service = StubSessionService(
            detail: makeDetail(state: "lobby", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        service.transitionResult = .success(
            makeDetail(state: "live", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let liveActivity = await StubLiveActivityControlling()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, liveActivity: liveActivity
        )
        await viewModel.load()

        await viewModel.goLive()

        let startCallCount = await liveActivity.startCallCount
        XCTAssertEqual(startCallCount, 1)
    }

    func testFinalizeEndsLiveActivity() async {
        let service = StubSessionService(
            detail: makeDetail(state: "debrief", yourRole: "interviewer", consentInterviewer: true, consentCandidate: true)
        )
        let signaling = StubSignalingChannel()
        let liveActivity = await StubLiveActivityControlling()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, liveActivity: liveActivity
        )
        await viewModel.load()

        await viewModel.finalize(grade: 90)

        let endCallCount = await liveActivity.endCallCount
        XCTAssertEqual(endCallCount, 1)
    }

    func testStopEndsLiveActivity() async {
        let service = StubSessionService(detail: makeDetail(state: "lobby", yourRole: "candidate"))
        let signaling = StubSignalingChannel()
        let liveActivity = await StubLiveActivityControlling()
        let viewModel = await SessionViewModel(
            sessionId: 42, service: service, signaling: signaling, liveActivity: liveActivity
        )
        await viewModel.load()

        await viewModel.stop()

        let endCallCount = await liveActivity.endCallCount
        XCTAssertEqual(endCallCount, 1)
    }
}
