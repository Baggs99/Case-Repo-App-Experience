/*
 * Purpose: Tests the on-device drill port — seed derivation vs. server reference
 *          values, per-op independent recomputation against the real bundled bank
 *          (catches port drift), recall shuffle tracking, and daily determinism.
 * Inputs: bundled Fixtures/drill_templates.json (verbatim webapp bank).
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class LocalDrillGeneratorTests: XCTestCase {
    private func makeGenerator() throws -> LocalDrillGenerator {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "drill_templates", withExtension: "json", subdirectory: "Fixtures"),
            "drill_templates.json fixture not bundled"
        )
        return try LocalDrillGenerator(templatePack: Data(contentsOf: url))
    }

    private func templates(of type: DrillType, _ gen: LocalDrillGenerator) -> [LocalDrillGenerator.Template] {
        gen.templates.filter { $0.drillType == type }
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Independent number-literal extraction (own regex, mirrors _NUM_RE).
    private func literals(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    // Independent recomputation of each mental_math answer — deliberately does NOT
    // call LocalDrillGenerator.applyOp. Own arithmetic, per the correctness contract.
    private func expectedAnswer(_ op: String, _ p: [String: Int]) -> Double {
        func v(_ k: String) -> Double { Double(p[k] ?? 0) }
        switch op {
        case "pct_change":           return (v("b") - v("a")) / v("a") * 100
        case "growth_compound":      return v("a") * (1 + v("g") / 100) * (1 + v("g") / 100)
        case "breakeven_units":      return v("fixed") / (v("price") - v("vc"))
        case "margin_pct":           return (v("rev") - v("cost")) / v("rev") * 100
        case "markup_price":         return v("cost") * (1 + v("markup") / 100)
        case "market_share_revenue": return v("market") * v("share") / 100
        case "per_capita":           return v("total") / v("pop")
        case "weighted_avg_2":       return (v("v1") * v("w1") + v("v2") * v("w2")) / (v("w1") + v("w2"))
        case "cagr_2yr_approx":      return (v("end") - v("start")) / v("start") / 2 * 100
        case "payback_months":       return v("invest") / v("monthly")
        default:                     return .nan
        }
    }

    // MARK: - Seed derivation matches the server value (byte-for-byte)

    func testSeedMatchesServerReference() {
        // Reference values from int(sha256("uid:date").hexdigest()[:8], 16).
        XCTAssertEqual(LocalDrillGenerator.seed(userId: 1, date: utcDate(2026, 7, 15)), 4_266_475_074)
        XCTAssertEqual(LocalDrillGenerator.seed(userId: 101, date: utcDate(2026, 7, 15)), 2_054_944_488)
        XCTAssertEqual(LocalDrillGenerator.seed(userId: 7, date: utcDate(2026, 1, 1)), 1_149_094_385)
    }

    // MARK: - Determinism

    func testSameSeedIdentical() throws {
        let gen = try makeGenerator()
        for t in gen.templates {
            XCTAssertEqual(gen.generate(template: t, seed: 42), gen.generate(template: t, seed: 42), t.key)
        }
    }

    func testDifferentSeedVariesParams() throws {
        let gen = try makeGenerator()
        let t = try XCTUnwrap(templates(of: .mentalMath, gen).first { $0.op == "pct_change" })
        let seen = Set((0..<25).map { gen.generate(template: t, seed: UInt32($0)).numbers })
        XCTAssertGreaterThanOrEqual(seen.count, 2)
    }

    // MARK: - Wire shape per type

    func testWireShapePerType() throws {
        let gen = try makeGenerator()

        let mm = gen.generate(template: templates(of: .mentalMath, gen)[0], seed: 7)
        XCTAssertEqual(mm.answer.kind, .numeric)
        XCTAssertNotNil(mm.answer.tolerancePct)
        XCTAssertNil(mm.choices)

        let ms = gen.generate(template: templates(of: .marketSizing, gen)[0], seed: 7)
        XCTAssertEqual(ms.answer.kind, .numeric)
        XCTAssertNotNil(ms.answer.toleranceFactor)

        let fr = gen.generate(template: templates(of: .frameworkRecall, gen)[0], seed: 7)
        XCTAssertEqual(fr.answer.kind, .choice)
        XCTAssertNotNil(fr.choices)
        XCTAssertNotNil(fr.answer.correctIndex)
    }

    // MARK: - Per-op correctness (independent recompute + negative case)

    func testMentalMathAnswersRecomputedIndependently() throws {
        let gen = try makeGenerator()
        var sawNegativePctChange = false
        for t in templates(of: .mentalMath, gen) {
            let op = try XCTUnwrap(t.op)
            for seed in 0..<64 {
                var rng = SplitMix64(seed: UInt64(seed))
                let params = LocalDrillGenerator.drawParams(t.params ?? [:], using: &rng)
                let expected = expectedAnswer(op, params)
                let got = try XCTUnwrap(gen.generate(template: t, seed: UInt32(seed)).answer.value)
                XCTAssertEqual(got, expected, accuracy: 1e-9, "\(t.key) seed=\(seed) params=\(params)")
                if op == "pct_change" && got < 0 { sawNegativePctChange = true }
            }
        }
        // Negative answers are by design (pct_change with b < a) — must be exercised.
        XCTAssertTrue(sawNegativePctChange, "expected at least one negative pct_change answer")
    }

    func testPctChangeOpProducesNegative() {
        // Deterministic negative case, independent of the draw.
        XCTAssertEqual(LocalDrillGenerator.applyOp("pct_change", ["a": 100, "b": 80]), -20, accuracy: 1e-9)
    }

    // MARK: - Market sizing

    func testMarketSizingAnswerAndNumbers() throws {
        let gen = try makeGenerator()
        for t in templates(of: .marketSizing, gen) {
            let unitParam = try XCTUnwrap(t.unitParam)
            let reference = try XCTUnwrap(t.referencePerUnit)
            for seed in 0..<25 {
                var rng = SplitMix64(seed: UInt64(seed))
                let params = LocalDrillGenerator.drawParams(t.params ?? [:], using: &rng)
                let drill = gen.generate(template: t, seed: UInt32(seed))
                let expected = reference * Double(params[unitParam] ?? 0)
                XCTAssertEqual(try XCTUnwrap(drill.answer.value), expected, accuracy: 1e-9, "\(t.key) seed=\(seed)")
                XCTAssertEqual(drill.numbers, literals(in: drill.prompt))
                XCTAssertTrue(drill.numbers.contains(String(params[unitParam] ?? 0)))
            }
        }
    }

    // MARK: - Framework recall shuffle tracks the correct answer

    func testRecallShuffleKeepsCorrectAnswer() throws {
        let gen = try makeGenerator()
        for t in templates(of: .frameworkRecall, gen) {
            let originalCorrect = try XCTUnwrap(t.choices)[try XCTUnwrap(t.correctIndex)]
            for seed in 0..<25 {
                let drill = gen.generate(template: t, seed: UInt32(seed))
                let choices = try XCTUnwrap(drill.choices)
                let idx = try XCTUnwrap(drill.answer.correctIndex)
                XCTAssertEqual(choices[idx], originalCorrect, "\(t.key) seed=\(seed)")
                XCTAssertEqual(Set(choices), Set(try XCTUnwrap(t.choices)), t.key)
            }
        }
    }

    // MARK: - numbers == every prompt literal, all types

    func testNumbersEqualPromptLiteralsAllTypes() throws {
        let gen = try makeGenerator()
        for t in gen.templates {
            for seed in 0..<5 {
                let drill = gen.generate(template: t, seed: UInt32(seed))
                XCTAssertEqual(drill.numbers, literals(in: drill.prompt), t.key)
            }
        }
    }

    // MARK: - dailyDrill determinism

    func testDailySameUserAndDateIdentical() throws {
        let gen = try makeGenerator()
        let date = utcDate(2026, 7, 15)
        XCTAssertEqual(gen.dailyDrill(userId: 101, date: date), gen.dailyDrill(userId: 101, date: date))
    }

    func testDailyVariesByDate() throws {
        let gen = try makeGenerator()
        let pairs = Set((1...10).map { d -> String in
            let drill = gen.dailyDrill(userId: 101, date: utcDate(2026, 7, d))
            return "\(drill.key)|\(drill.prompt)"
        })
        XCTAssertGreaterThanOrEqual(pairs.count, 2)
    }

    func testDailyVariesByUser() throws {
        let gen = try makeGenerator()
        let date = utcDate(2026, 7, 15)
        let keys = Set((1...10).map { gen.dailyDrill(userId: $0, date: date).key })
        XCTAssertGreaterThanOrEqual(keys.count, 2)
    }

    func testDailyTypeSelectionCoversAllThree() throws {
        let gen = try makeGenerator()
        let date = utcDate(2026, 7, 15)
        let types = Set((1..<60).map { gen.dailyDrill(userId: $0, date: date).drillType })
        XCTAssertEqual(types, [.mentalMath, .marketSizing, .frameworkRecall])
    }
}
