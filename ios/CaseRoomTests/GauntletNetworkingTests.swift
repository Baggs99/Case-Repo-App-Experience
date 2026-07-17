/*
 * Purpose: Unit tests for the F7 Task 1 gauntlet-submit/boards/trends
 *          Codables added to HomeModels.swift — pure decode/encode against
 *          literal JSON matching the B8-pinned payloads (bgap-b8-report.md
 *          "Interfaces delivered"). No live network: a local decoder/encoder
 *          mirrors APIClient's private configuration exactly (see
 *          APIClientTests.fixtureDecoder for the same pattern).
 * Inputs: literal JSON strings.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class GauntletNetworkingTests: XCTestCase {

    // Mirrors APIClient's private decoder/encoder configuration exactly.
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    // MARK: - GauntletResult (nulls)

    func testGauntletResultDecodesWithNullPercentileAndNullGroup() throws {
        let json = #"""
        {"score": 0.5, "slots_correct": 3, "slots": 6, "points_awarded": 0,
         "daily_percentile": null, "group": null, "school_percentile": null,
         "vs_peers_delta": null, "weak_section": null, "streak": 1, "set_key": "2026-07-17"}
        """#
        let result = try decoder().decode(GauntletResult.self, from: Data(json.utf8))

        XCTAssertEqual(result.score, 0.5)
        XCTAssertEqual(result.slotsCorrect, 3)
        XCTAssertEqual(result.slots, 6)
        XCTAssertEqual(result.pointsAwarded, 0)
        XCTAssertNil(result.dailyPercentile)
        XCTAssertNil(result.group)
        XCTAssertNil(result.schoolPercentile)
        XCTAssertNil(result.vsPeersDelta)
        XCTAssertNil(result.weakSection)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.setKey, "2026-07-17")
    }

    // MARK: - SchoolBoard (scope=school)

    func testSchoolBoardDecodesPopulated() throws {
        let json = #"""
        {"scope": "school", "school": {"school_id": 1, "name": "Wharton",
          "campus_city": "Philadelphia", "avg_member_percentile": 72.5, "rank": 3},
         "your_percentile": 60.0}
        """#
        let board = try decoder().decode(SchoolBoard.self, from: Data(json.utf8))

        XCTAssertEqual(board.scope, "school")
        XCTAssertEqual(board.school?.schoolId, 1)
        XCTAssertEqual(board.school?.name, "Wharton")
        XCTAssertEqual(board.school?.campusCity, "Philadelphia")
        XCTAssertEqual(board.school?.avgMemberPercentile, 72.5)
        XCTAssertEqual(board.school?.rank, 3)
        XCTAssertEqual(board.yourPercentile, 60.0)
    }

    func testSchoolBoardDecodesNullSchoolAndNullPercentile() throws {
        let json = #"{"scope": "school", "school": null, "your_percentile": null}"#
        let board = try decoder().decode(SchoolBoard.self, from: Data(json.utf8))

        XCTAssertEqual(board.scope, "school")
        XCTAssertNil(board.school)
        XCTAssertNil(board.yourPercentile)
    }

    // MARK: - GlobalBoard (scope=global)

    func testGlobalBoardDecodesPopulated() throws {
        let json = #"{"scope": "global", "your_percentile": 88.0}"#
        let board = try decoder().decode(GlobalBoard.self, from: Data(json.utf8))

        XCTAssertEqual(board.scope, "global")
        XCTAssertEqual(board.yourPercentile, 88.0)
    }

    func testGlobalBoardDecodesNullPercentile() throws {
        let json = #"{"scope": "global", "your_percentile": null}"#
        let board = try decoder().decode(GlobalBoard.self, from: Data(json.utf8))

        XCTAssertEqual(board.scope, "global")
        XCTAssertNil(board.yourPercentile)
    }

    // MARK: - SchoolsBoard (scope=schools)

    func testSchoolsBoardDecodesList() throws {
        let json = #"""
        {"scope": "schools", "schools": [
          {"school_id": 1, "name": "Wharton", "campus_city": "Philadelphia",
           "avg_member_percentile": 72.5, "rank": 1},
          {"school_id": 2, "name": "Yale SOM", "campus_city": "New Haven",
           "avg_member_percentile": 65.0, "rank": 2}]}
        """#
        let board = try decoder().decode(SchoolsBoard.self, from: Data(json.utf8))

        XCTAssertEqual(board.scope, "schools")
        XCTAssertEqual(board.schools.count, 2)
        XCTAssertEqual(board.schools[0].name, "Wharton")
        XCTAssertEqual(board.schools[0].id, 1)
        XCTAssertEqual(board.schools[1].campusCity, "New Haven")
    }

    // MARK: - GauntletTrends

    func testGauntletTrendsDecodesWithNullWeakest() throws {
        let json = #"""
        {"daily": [{"date": "2026-07-16", "score": 4.0}, {"date": "2026-07-17", "score": 6.0}],
         "by_type": [{"drill_type": "mental_math", "attempts": 10, "correct": 8, "accuracy": 0.8}],
         "weakest": null}
        """#
        let trends = try decoder().decode(GauntletTrends.self, from: Data(json.utf8))

        XCTAssertEqual(trends.daily.count, 2)
        XCTAssertEqual(trends.daily[1].date, "2026-07-17")
        XCTAssertEqual(trends.daily[1].score, 6.0)
        XCTAssertEqual(trends.byType.count, 1)
        XCTAssertEqual(trends.byType[0].drillType, "mental_math")
        XCTAssertEqual(trends.byType[0].id, "mental_math")
        XCTAssertEqual(trends.byType[0].accuracy, 0.8)
        XCTAssertNil(trends.weakest)
    }

    func testGauntletTrendsDecodesWithWeakest() throws {
        let json = #"""
        {"daily": [], "by_type": [], "weakest": "market_sizing"}
        """#
        let trends = try decoder().decode(GauntletTrends.self, from: Data(json.utf8))

        XCTAssertEqual(trends.weakest, "market_sizing")
    }

    // MARK: - GauntletAttempt encoding (per-slot SUBSET, snake_case)

    func testNumericAttemptEncodesValueAndDurationOmitsChoiceIndex() throws {
        let attempt = GauntletAttempt(slot: 0, value: 42.5, choiceIndex: nil, durationMs: 1200)
        let data = try encoder().encode(attempt)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["slot", "value", "duration_ms"])
        XCTAssertEqual(object["slot"] as? Int, 0)
        XCTAssertEqual(object["value"] as? Double, 42.5)
        XCTAssertEqual(object["duration_ms"] as? Int, 1200)
        XCTAssertNil(object["choice_index"])
    }

    func testChoiceAttemptEncodesChoiceIndexAndDurationOmitsValue() throws {
        let attempt = GauntletAttempt(slot: 1, value: nil, choiceIndex: 2, durationMs: 800)
        let data = try encoder().encode(attempt)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["slot", "choice_index", "duration_ms"])
        XCTAssertEqual(object["slot"] as? Int, 1)
        XCTAssertEqual(object["choice_index"] as? Int, 2)
        XCTAssertEqual(object["duration_ms"] as? Int, 800)
        XCTAssertNil(object["value"])
    }
}
