/*
 * Purpose: Unit tests for OnboardingViewModel — the step machine (happy path +
 *          each failure branch) and the SEAM invariant that SessionStore stays
 *          unauthenticated through every step, flipping to authenticated ONLY
 *          after finish(). Reuses the DEBUG StubOnboardingBackend fixture.
 * Inputs: StubOnboardingBackend (in-memory); StubURLProtocol for the /me hop
 *         behind SessionStore.finishOnboarding().
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private func makeVM(backend: StubOnboardingBackend = StubOnboardingBackend(),
                        store: SessionStore = SessionStore()) -> OnboardingViewModel {
        OnboardingViewModel(service: backend, oauthStarter: backend, profileService: backend, sessionStore: store)
    }

    // MARK: - Happy path

    func testHappyPathWalksWelcomeToDone() async {
        let vm = makeVM()
        XCTAssertEqual(vm.step, .welcome)

        vm.goToEmail()
        XCTAssertEqual(vm.step, .email)

        vm.email = OnboardingFixtures.email
        await vm.submitEmail()
        XCTAssertEqual(vm.step, .passcode)

        vm.code = "123456"
        await vm.submitCode()
        XCTAssertEqual(vm.step, .account)
        XCTAssertEqual(vm.user?.email, OnboardingFixtures.email)

        vm.displayName = OnboardingFixtures.displayName
        await vm.submitAccount()
        XCTAssertEqual(vm.step, .group)

        vm.inviteCode = OnboardingFixtures.inviteCode
        await vm.joinGroup()
        XCTAssertEqual(vm.step, .done)
        XCTAssertNil(vm.errorText)
    }

    // MARK: - progressStep mapping

    func testProgressStepMapping() {
        let vm = makeVM()
        let expected: [OnboardingViewModel.Step: Int] = [
            .welcome: 0, .email: 1, .passcode: 2, .account: 3, .group: 4, .done: 5,
        ]
        for (step, index) in expected {
            vm.step = step
            XCTAssertEqual(vm.progressStep, index, "progressStep for \(step)")
        }
    }

    // MARK: - Failure branches

    func testSubmitEmailRequestFailureStaysOnEmail() async {
        let backend = StubOnboardingBackend()
        backend.forceRequestFailure = true
        let vm = makeVM(backend: backend)
        vm.step = .email
        vm.email = OnboardingFixtures.email

        await vm.submitEmail()

        // A code that was never sent must not surface a passcode screen.
        XCTAssertEqual(vm.step, .email)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isSubmitting)
    }

    func testSubmitEmailGuardsEmpty() async {
        let backend = StubOnboardingBackend()
        let vm = makeVM(backend: backend)
        vm.step = .email
        vm.email = "   "

        await vm.submitEmail()

        XCTAssertEqual(vm.step, .email)
        XCTAssertEqual(backend.requestOTPCalls, 0)
    }

    func testSubmitCodeUnauthorizedStaysAndClearsCode() async {
        let backend = StubOnboardingBackend()
        backend.forceVerify401 = true
        let vm = makeVM(backend: backend)
        vm.step = .passcode
        vm.code = "000000"

        await vm.submitCode()

        XCTAssertEqual(vm.step, .passcode)
        XCTAssertEqual(vm.code, "")
        XCTAssertNotNil(vm.errorText)
        XCTAssertNil(vm.user)
    }

    func testSubmitAccountFailureSetsError() async {
        let backend = StubOnboardingBackend()
        backend.forceProfileFailure = true
        let vm = makeVM(backend: backend)
        vm.step = .account
        vm.displayName = OnboardingFixtures.displayName

        await vm.submitAccount()

        XCTAssertEqual(vm.step, .account)
        XCTAssertNotNil(vm.errorText)
    }

    func testStartOAuthSuccessAdvancesToGroup() async {
        let backend = StubOnboardingBackend()
        let vm = makeVM(backend: backend)
        vm.step = .account

        await vm.startOAuth(.google)

        XCTAssertEqual(vm.step, .group)
        XCTAssertEqual(backend.startedProviders, [.google])
        XCTAssertNil(vm.errorText)
    }

    func testStartOAuthUnavailableStaysOnAccount() async {
        let backend = StubOnboardingBackend()
        backend.forceOAuthUnavailable = true
        let vm = makeVM(backend: backend)
        vm.step = .account

        await vm.startOAuth(.linkedin)

        XCTAssertEqual(vm.step, .account)
        XCTAssertNotNil(vm.errorText)
    }

    func testJoinGroupUnknownCodeStaysOnGroup() async {
        let backend = StubOnboardingBackend()
        backend.forceJoin404 = true
        let vm = makeVM(backend: backend)
        vm.step = .group
        vm.inviteCode = "NOPE"

        await vm.joinGroup()

        XCTAssertEqual(vm.step, .group)
        XCTAssertNotNil(vm.errorText)
    }

    func testSkipGroupGoesToDone() {
        let vm = makeVM()
        vm.step = .group

        vm.skipGroup()

        XCTAssertEqual(vm.step, .done)
    }

    func testBackStepsThroughFlow() {
        let vm = makeVM()
        vm.step = .group; vm.back(); XCTAssertEqual(vm.step, .account)
        vm.back(); XCTAssertEqual(vm.step, .passcode)
        vm.back(); XCTAssertEqual(vm.step, .email)
        vm.back(); XCTAssertEqual(vm.step, .welcome)
        vm.back(); XCTAssertEqual(vm.step, .welcome)   // no-op at the intro
    }

    // MARK: - SEAM: auth flips only at finish()

    func testSessionStoreStaysUnauthenticatedUntilFinish() async {
        StubURLProtocol.reset()
        StubURLProtocol.stubs.append(
            .init(statusCode: 200,
                  data: Data(#"{"id": 7, "email": "amara@yale.edu", "name": "Amara Osei"}"#.utf8),
                  headers: ["Content-Type": "application/json"])
        )
        let meClient = APIClient(session: URLSession(configuration: StubURLProtocol.sessionConfiguration))
        let store = SessionStore(client: meClient)
        let vm = makeVM(store: store)

        XCTAssertFalse(store.isAuthenticated)          // welcome
        vm.email = OnboardingFixtures.email

        vm.goToEmail();            XCTAssertFalse(store.isAuthenticated)
        await vm.submitEmail();     XCTAssertFalse(store.isAuthenticated)   // .passcode
        vm.code = "123456"
        await vm.submitCode();      XCTAssertFalse(store.isAuthenticated)   // .account (user held locally)
        vm.displayName = OnboardingFixtures.displayName
        await vm.submitAccount();   XCTAssertFalse(store.isAuthenticated)   // .group

        // The verify step already set a cookie locally; only finish() cashes it.
        await vm.finish()
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.user?.id, 7)
    }

    // finish() must surface an error (not sit inert) if bootstrap fails to
    // authenticate — e.g. the post-verify cookie went stale.
    func testFinishSurfacesErrorWhenBootstrapDoesNotAuthenticate() async {
        StubURLProtocol.reset()
        StubURLProtocol.stubs.append(.init(statusCode: 401, data: Data(), headers: [:]))
        let meClient = APIClient(session: URLSession(configuration: StubURLProtocol.sessionConfiguration))
        let store = SessionStore(client: meClient)
        let vm = makeVM(store: store)
        vm.step = .done

        await vm.finish()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNotNil(vm.errorText)
    }
}
