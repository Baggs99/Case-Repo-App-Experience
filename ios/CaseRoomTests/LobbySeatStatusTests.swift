/*
 * Purpose: Unit tests for LobbySeatStatus.resolve — the pure mapping from a
 *          seat's consent/present/knock flags to the canvas 4a lobby chip
 *          (READY / JOINED / KNOCKING / WAITING / DECLINED) and its green-state
 *          classification. Guards the T2 lobby presentation contract.
 * Inputs: none.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class LobbySeatStatusTests: XCTestCase {

    func testConsentedIsReady() {
        XCTAssertEqual(
            LobbySeatStatus.resolve(consented: true, present: true, knocking: false, denied: false),
            .ready)
        XCTAssertEqual(LobbySeatStatus.ready.label, "READY")
        XCTAssertTrue(LobbySeatStatus.ready.isPresentState)
    }

    func testPresentButNotConsentedIsJoined() {
        XCTAssertEqual(
            LobbySeatStatus.resolve(consented: false, present: true, knocking: false, denied: false),
            .joined)
        XCTAssertEqual(LobbySeatStatus.joined.label, "JOINED")
        XCTAssertTrue(LobbySeatStatus.joined.isPresentState)
    }

    func testAbsentIsWaiting() {
        XCTAssertEqual(
            LobbySeatStatus.resolve(consented: false, present: false, knocking: false, denied: false),
            .waiting)
        XCTAssertFalse(LobbySeatStatus.waiting.isPresentState)
    }

    func testKnockingTakesPrecedenceOverPresence() {
        XCTAssertEqual(
            LobbySeatStatus.resolve(consented: false, present: false, knocking: true, denied: false),
            .knocking)
        XCTAssertFalse(LobbySeatStatus.knocking.isPresentState)
    }

    func testDeniedWinsOverEverything() {
        XCTAssertEqual(
            LobbySeatStatus.resolve(consented: true, present: true, knocking: true, denied: true),
            .declined)
        XCTAssertFalse(LobbySeatStatus.declined.isPresentState)
    }

    // Canvas 4a: candidate consented (You → READY), interviewer present, not yet
    // consented (M. Lindqvist → JOINED) — the exact fixture the shot captures.
    func testCanvasLobbyPairing() {
        let mine = LobbySeatStatus.resolve(consented: true, present: true, knocking: false, denied: false)
        let peer = LobbySeatStatus.resolve(consented: false, present: true, knocking: false, denied: false)
        XCTAssertEqual(mine, .ready)
        XCTAssertEqual(peer, .joined)
    }
}
