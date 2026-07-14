/*
 * Purpose: Unit tests for SessionStore — proves logout() clears user and
 *          invokes the injected onLogout hook (used at app launch to reset
 *          PushCoordinator's registration guard).
 * Inputs: none (StubURLProtocol-backed APIClient, reused from APIClientTests).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class SessionStoreTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let session = URLSession(configuration: StubURLProtocol.sessionConfiguration)
        client = APIClient(session: session)
    }

    func testLogoutInvokesOnLogoutHookAndClearsUser() async {
        StubURLProtocol.stubs.append(
            .init(statusCode: 204, data: Data(), headers: [:])
        )
        let store = SessionStore(client: client)
        store.user = User(id: 1, email: "a@yale.edu", name: "Alice Dev")

        var onLogoutCalled = false
        store.onLogout = { onLogoutCalled = true }

        await store.logout()

        XCTAssertTrue(onLogoutCalled)
        XCTAssertNil(store.user)
    }

    func testLogoutInvokesOnLogoutHookEvenWhenServerCallFails() async {
        // No stub queued — StubURLProtocol fails with .unknown, exercising
        // logout()'s best-effort catch that still clears local state.
        let store = SessionStore(client: client)
        store.user = User(id: 1, email: "a@yale.edu", name: "Alice Dev")

        var onLogoutCalled = false
        store.onLogout = { onLogoutCalled = true }

        await store.logout()

        XCTAssertTrue(onLogoutCalled)
        XCTAssertNil(store.user)
    }
}
