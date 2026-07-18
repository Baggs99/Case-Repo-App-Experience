/*
 * Purpose: Unit tests for the F9 onboarding seams — OnboardingService (OTP
 *          request/verify, group join + status mapping) and SessionStore's
 *          finishOnboarding() bootstrap hook.
 * Inputs: canned JSON via StubURLProtocol (reused from APIClientTests).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class OnboardingServiceTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let session = URLSession(configuration: StubURLProtocol.sessionConfiguration)
        client = APIClient(session: session)
    }

    private func stub(_ json: String, status: Int) {
        StubURLProtocol.stubs.append(
            .init(statusCode: status, data: Data(json.utf8), headers: ["Content-Type": "application/json"])
        )
    }

    // MARK: - requestOTP

    func testRequestOTPSucceedsOn202AndPostsEmail() async throws {
        stub(#"{"status": "ok"}"#, status: 202)

        try await client.requestOTP(email: "amara@yale.edu")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/auth/otp/request")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["email"] as? String, "amara@yale.edu")
    }

    func testRequestOTPSucceedsOnBare200() async throws {
        stub(#"{"status": "ok"}"#, status: 200)

        try await client.requestOTP(email: "amara@yale.edu")

        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.url?.path, "/api/v1/auth/otp/request")
    }

    func testRequestOTPTransportFailureThrows() async {
        // No stub queued — StubURLProtocol fails with URLError(.unknown), which
        // APIClient wraps as APIError.transport.
        do {
            try await client.requestOTP(email: "amara@yale.edu")
            XCTFail("expected a transport failure")
        } catch APIError.transport {
            // expected
        } catch {
            XCTFail("expected APIError.transport, got \(error)")
        }
    }

    // MARK: - verifyOTP

    func testVerifyOTPDecodesUserOn200() async throws {
        stub(#"{"user": {"id": 7, "email": "amara@yale.edu", "name": "Amara Osei"}}"#, status: 200)

        let user = try await client.verifyOTP(email: "amara@yale.edu", code: "123456")

        XCTAssertEqual(user.id, 7)
        XCTAssertEqual(user.email, "amara@yale.edu")
        XCTAssertEqual(user.name, "Amara Osei")

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/auth/otp/verify")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["email"] as? String, "amara@yale.edu")
        XCTAssertEqual(body["code"] as? String, "123456")
    }

    func testVerifyOTPThrowsUnauthorizedOn401() async {
        stub(#"{"detail": "invalid_code"}"#, status: 401)

        do {
            _ = try await client.verifyOTP(email: "amara@yale.edu", code: "000000")
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("expected APIError.unauthorized, got \(error)")
        }
    }

    // MARK: - joinGroup

    func testJoinGroupDecodesSubsetOn200() async throws {
        // Server returns all six keys; JoinedGroup decodes only id/name/already_member.
        stub(#"""
        {"id": 14, "name": "Yale SOM 26", "school_id": 2, "invite_code": "C-14",
         "role": "member", "already_member": false}
        """#, status: 200)

        let group = try await client.joinGroup(inviteCode: "C-14")

        XCTAssertEqual(group.id, 14)
        XCTAssertEqual(group.name, "Yale SOM 26")
        XCTAssertFalse(group.alreadyMember)

        let request = StubURLProtocol.recordedRequests.first!
        XCTAssertEqual(request.url?.path, "/api/v1/groups/join")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
        XCTAssertEqual(body["invite_code"] as? String, "C-14")
    }

    func testJoinGroupThrowsUnknownInviteCodeOn404() async {
        stub(#"{"detail": "Unknown invite code"}"#, status: 404)

        do {
            _ = try await client.joinGroup(inviteCode: "NOPE")
            XCTFail("expected unknownInviteCode")
        } catch OnboardingError.unknownInviteCode {
            // expected
        } catch {
            XCTFail("expected OnboardingError.unknownInviteCode, got \(error)")
        }
    }

    // MARK: - SessionStore.finishOnboarding

    func testFinishOnboardingFlipsIsAuthenticatedWhenMeReturnsUser() async {
        // me() decodes a bare User at /api/v1/me (see APIClient.me / testRealFixture_me).
        stub(#"{"id": 7, "email": "amara@yale.edu", "name": "Amara Osei"}"#, status: 200)
        let store = SessionStore(client: client)
        XCTAssertFalse(store.isAuthenticated)

        await store.finishOnboarding()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.user?.id, 7)
    }

    func testFinishOnboardingStaysUnauthenticatedOn401() async {
        stub(#"{"detail": "not_authenticated"}"#, status: 401)
        let store = SessionStore(client: client)

        await store.finishOnboarding()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.user)
    }
}
