/*
 * Purpose: Unit tests for ExhibitsViewModel — stubbed SessionService proving
 *          load() pre-fetches the manifest + ciphertext blobs locked, and
 *          handleReveal decrypts a known-answer AES-GCM fixture and reveals
 *          it, while a reveal for an unknown exhibit id is a no-op.
 * Inputs: none (in-memory stub service + a real server-produced fixture).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class StubExhibitsSessionService: SessionService {
    var exhibitsResult: Result<[ExhibitMeta], Error>
    var exhibitBlobResult: Result<Data, Error>

    init(exhibits: [ExhibitMeta], blob: Data) {
        self.exhibitsResult = .success(exhibits)
        self.exhibitBlobResult = .success(blob)
    }

    func exhibits(id: Int) async throws -> [ExhibitMeta] {
        try exhibitsResult.get()
    }

    func exhibitBlob(id: Int, exhibitId: Int) async throws -> Data {
        try exhibitBlobResult.get()
    }

    // Unused by ExhibitsViewModel — required by the SessionService protocol.
    func sessionDetail(id: Int) async throws -> SessionDetail { fatalError("not used") }
    func setConsent(id: Int, consent: Bool) async throws -> SessionDetail { fatalError("not used") }
    func transition(id: Int, target: String) async throws -> SessionDetail { fatalError("not used") }
    func rubric(id: Int) async throws -> RubricState { fatalError("not used") }
    func saveRubric(id: Int, items: [String: RubricItemScore], notesMd: String) async throws -> Double { fatalError("not used") }
    func reveal(id: Int, exhibitId: Int) async throws { fatalError("not used") }
    func uploadRecordingChunk(id: Int, seq: Int, mime: String, blob: Data) async throws { fatalError("not used") }
    func completeRecording(id: Int) async throws { fatalError("not used") }
    func finalize(id: Int, grade: Double?) async throws -> Finalized { fatalError("not used") }
}

final class ExhibitsViewModelTests: XCTestCase {
    // Real server-produced AES-GCM fixture — do not alter these values.
    private let exhibitId = 5
    private let keyB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    private let ivB64 = "AAECAwQFBgcICQoL"
    private let ctB64 = "BGOlfpeKrXatJO/j2IsRGaOw7kyEDi0ZGO61y1pEacFpMMyF26Rhvho622aW56FxGrq8AP7NGw=="
    private let expectedPlaintextB64 = "Q2FzZVJvb20gZXhoaWJpdCBmaXh0dXJlIIlQTkctaXNoIGJ5dGVz"

    private func makeMeta() -> ExhibitMeta {
        ExhibitMeta(exhibitId: exhibitId, idx: 0, sourcePages: "1", width: 100, height: 100, bytes: 64, ivB64: ivB64)
    }

    private func makeViewModel() async -> ExhibitsViewModel {
        let service = StubExhibitsSessionService(exhibits: [makeMeta()], blob: Data(base64Encoded: ctB64)!)
        return await ExhibitsViewModel(sessionId: 42, service: service)
    }

    // MARK: - handleReveal

    func testHandleRevealDecryptsAndTransitionsLockedToRevealed() async {
        let viewModel = await makeViewModel()
        await viewModel.load()

        let lockedState = await viewModel.state(for: exhibitId)
        XCTAssertEqual(lockedState, .locked)

        await viewModel.handleReveal(exhibitId: exhibitId, keyB64: keyB64)

        let revealedState = await viewModel.state(for: exhibitId)
        guard case .revealed(let data) = revealedState else {
            return XCTFail("Expected exhibit to be revealed")
        }
        XCTAssertEqual(data, Data(base64Encoded: expectedPlaintextB64)!)
    }

    func testHandleRevealIgnoresUnknownExhibitId() async {
        let viewModel = await makeViewModel()
        await viewModel.load()

        await viewModel.handleReveal(exhibitId: 999, keyB64: keyB64)

        let state = await viewModel.state(for: exhibitId)
        XCTAssertEqual(state, .locked)
    }
}
