/*
 * Purpose: Decode tests for the drill wire models against real captured
 *          backend fixtures (all three drill types) and the DashboardStats
 *          back-compat change (new streak keys optional).
 * Inputs: JSON fixtures under ios/CaseRoomTests/Fixtures (drill_daily/sizing/choice).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class DrillModelsTests: XCTestCase {
    private struct DailyResponse: Decodable { let drill: Drill; let date: String }

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).json not bundled")
        }
        return try Data(contentsOf: url)
    }

    private func drillDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - numeric (mental_math, tolerance_pct)

    func testDecodeDailyMentalMath() throws {
        let data = try loadFixture("drill_daily")
        let response = try drillDecoder().decode(DailyResponse.self, from: data)
        let drill = response.drill

        XCTAssertEqual(response.date, "2026-07-16")
        XCTAssertEqual(drill.key, "mm_markup_price")
        XCTAssertEqual(drill.drillType, .mentalMath)
        XCTAssertNil(drill.choices)
        XCTAssertEqual(drill.answer.kind, .numeric)
        XCTAssertEqual(drill.answer.value, 75.0)
        XCTAssertEqual(drill.answer.tolerancePct, 2.0)
        XCTAssertNil(drill.answer.toleranceFactor)
        XCTAssertNil(drill.answer.correctIndex)
        // numbers match the prompt literals verbatim (Task 6 FM validator depends on this).
        XCTAssertEqual(drill.numbers, ["50", "50"])
        XCTAssertFalse(drill.explanation.isEmpty)
    }

    // MARK: - numeric (market_sizing, tolerance_factor)

    func testDecodeSizingFactor() throws {
        let data = try loadFixture("drill_sizing")
        let response = try drillDecoder().decode(DailyResponse.self, from: data)
        let drill = response.drill

        XCTAssertEqual(drill.key, "ms_pharmacies")
        XCTAssertEqual(drill.drillType, .marketSizing)
        XCTAssertNil(drill.choices)
        XCTAssertEqual(drill.answer.kind, .numeric)
        XCTAssertEqual(drill.answer.value, 1590.0)
        XCTAssertEqual(drill.answer.toleranceFactor, 2.0)
        XCTAssertNil(drill.answer.tolerancePct)
        XCTAssertEqual(drill.numbers, ["6"])
    }

    // MARK: - choice (framework_recall)

    func testDecodeChoice() throws {
        let data = try loadFixture("drill_choice")
        let response = try drillDecoder().decode(DailyResponse.self, from: data)
        let drill = response.drill

        XCTAssertEqual(drill.key, "fr_four_ps")
        XCTAssertEqual(drill.drillType, .frameworkRecall)
        XCTAssertEqual(drill.choices?.count, 4)
        XCTAssertEqual(drill.answer.kind, .choice)
        XCTAssertEqual(drill.answer.correctIndex, 1)
        XCTAssertNil(drill.answer.value)
        XCTAssertNil(drill.answer.tolerancePct)
        XCTAssertNil(drill.answer.toleranceFactor)
    }

    // MARK: - Equatable round-trip

    func testDrillEquatable() throws {
        let data = try loadFixture("drill_daily")
        let a = try drillDecoder().decode(DailyResponse.self, from: data).drill
        let b = try drillDecoder().decode(DailyResponse.self, from: data).drill
        XCTAssertEqual(a, b)
    }

    // MARK: - DashboardStats back-compat

    func testDashboardStatsDecodesWithNewKeys() throws {
        let json = Data(#"""
        {"sessions_finalized": 4, "streak_weeks": 2, "next_session": null,
         "streak_days": 5, "drill_done_today": true}
        """#.utf8)
        let stats = try drillDecoder().decode(DashboardStats.self, from: json)
        XCTAssertEqual(stats.sessionsFinalized, 4)
        XCTAssertEqual(stats.streakDays, 5)
        XCTAssertEqual(stats.drillDoneToday, true)
    }

    func testDashboardStatsDecodesWithoutNewKeys() throws {
        // Old fixture shape (no streak_days/drill_done_today) must still decode.
        let json = Data(#"""
        {"sessions_finalized": 4, "streak_weeks": 2, "next_session": null}
        """#.utf8)
        let stats = try drillDecoder().decode(DashboardStats.self, from: json)
        XCTAssertEqual(stats.sessionsFinalized, 4)
        XCTAssertNil(stats.streakDays)
        XCTAssertNil(stats.drillDoneToday)
    }
}
