/*
 * Purpose: Unit tests for the F5-T4 live-screen presentation logic — the MM:SS
 *          clock formatter, the CASE/EX new-dot derivation, the pill/panel/toast
 *          labels, and the revealed-exhibit content decode (including the full
 *          fixture path: the byte-for-byte ExhibitCrypto decrypt of the Nordic
 *          fixture ciphertext into structured table + unit-cost-bar content).
 * Inputs: none.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class LivePresentationTests: XCTestCase {

    // MARK: - Clock formatter

    func testClockFormatterClampsAndZeroPads() {
        XCTAssertEqual(SessionClock.mmss(0), "00:00")
        XCTAssertEqual(SessionClock.mmss(5), "00:05")
        XCTAssertEqual(SessionClock.mmss(65), "01:05")
        XCTAssertEqual(SessionClock.mmss(762), "12:42")   // canvas 4b frozen time
        XCTAssertEqual(SessionClock.mmss(3600), "60:00")
        XCTAssertEqual(SessionClock.mmss(-3), "00:00")    // never negative
    }

    // MARK: - New-dot derivation

    func testNewDotIsRevealedButUnseen() {
        XCTAssertEqual(LivePresentation.newDotIds(revealed: [501, 502], seen: []), [501, 502])
        XCTAssertEqual(LivePresentation.newDotIds(revealed: [501, 502], seen: [501]), [502])
        XCTAssertEqual(LivePresentation.newDotIds(revealed: [501], seen: [501]), [])
        // Seen ids that aren't (yet) revealed don't produce phantom dots.
        XCTAssertEqual(LivePresentation.newDotIds(revealed: [], seen: [501]), [])
    }

    func testLabels() {
        XCTAssertEqual(LivePresentation.pillLabel(idx: 0), "EX 01")
        XCTAssertEqual(LivePresentation.pillLabel(idx: 1), "EX 02")
        XCTAssertEqual(LivePresentation.panelLabel(idx: 0), "EXHIBIT 01")
        XCTAssertEqual(LivePresentation.revealToast(idx: 0), "Exhibit 01 released")
    }

    // MARK: - Exhibit content decode

    func testDecodeRejectsNonStructuredPayload() {
        // A production image exhibit isn't JSON — decode returns nil so the view
        // falls back to the existing UIImage path rather than crashing.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertNil(ExhibitContent.decode(from: png))
    }

    func testDecodeHonoursMissingOptionalFlags() throws {
        let json = Data("""
        { "title": "T", "table": { "columns": ["A"], "rows": [ { "cells": ["x"] } ] } }
        """.utf8)
        let content = try XCTUnwrap(ExhibitContent.decode(from: json))
        // total/highlight omitted must decode (optional), not throw.
        XCTAssertNil(content.table?.rows.first?.total)
        XCTAssertNil(content.bars)
    }

    // The whole fixture pipeline: the fixture ciphertext, opened by the UNCHANGED
    // ExhibitCrypto decrypt seam, is the exact Nordic table + unit-cost bars.
    func testFixtureCiphertextDecryptsToNordicContent() throws {
        let plaintext = try ExhibitCrypto.decrypt(
            ciphertext: SessionFixtures.liveExhibitBlob,
            keyB64: SessionFixtures.liveExhibitKeyB64,
            ivB64: SessionFixtures.liveExhibitIVB64)
        let content = try XCTUnwrap(ExhibitContent.decode(from: plaintext))

        XCTAssertEqual(content.title, "Nordic domestic market — volumes & fares")
        XCTAssertEqual(content.releasedAt, "11:58")

        let table = try XCTUnwrap(content.table)
        XCTAssertEqual(table.columns, ["COUNTRY", "PAX / YR", "AVG FARE"])
        XCTAssertEqual(table.rows.count, 4)
        XCTAssertEqual(table.rows[0].cells, ["Norway", "6.1M", "€92"])
        XCTAssertEqual(table.rows.last?.cells, ["Total", "14.0M", "€95"])
        XCTAssertEqual(table.rows.last?.total, true)
        XCTAssertEqual(table.rows[0].total, false)

        let bars = try XCTUnwrap(content.bars)
        XCTAssertEqual(bars.title, "Competitor unit costs — € cents per seat-km")
        XCTAssertEqual(bars.scaleMax, 7.0)
        XCTAssertEqual(bars.items.map(\.label), ["Skanwing", "NorAir", "FinnJet"])
        XCTAssertEqual(bars.items.map(\.value), [4.1, 5.3, 6.0])
        XCTAssertEqual(bars.items.first?.highlight, true)   // lowest cost = the single green
    }
}
