/*
 * Purpose: On-device Swift port of webapp/drills.py — a deterministic daily-drill
 *          interpreter over the cached template bank (seed, op table, param draws).
 * Inputs: init(templatePack:) the raw {version, templates} bank JSON bytes;
 *         dailyDrill(userId:date:) a user id + a Date (formatted UTC yyyy-MM-dd).
 * Outputs: pure Drill values — no I/O, no clock reads, no network.
 * Run: try LocalDrillGenerator(templatePack: data).dailyDrill(userId: 1, date: Date())
 *
 * Determinism note: the SHA256 SEED VALUE matches the server byte-for-byte, so the
 * drill TYPE (seed % 3) matches too. The template choice and param draws use the
 * inline SplitMix64 below, NOT Python's Mersenne Twister — so the concrete numbers
 * differ from the server. Determinism holds per-device-per-day only; cross-platform
 * draw-match is deliberately NOT a requirement. Draw order is sorted param-key so it
 * is stable across app launches regardless of Dictionary hash randomization.
 */

import Foundation
import CryptoKit

// Inline seedable PRNG (SplitMix64). SystemRandomNumberGenerator is non-seedable;
// this gives reproducible per-device draws from the daily seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct LocalDrillGenerator {
    // One bank template (mirrors a drill_templates.json entry). Decoded with
    // .convertFromSnakeCase; param names carry no underscores so the strategy
    // leaves the params dictionary keys untouched.
    struct Template: Decodable {
        let key: String
        let drillType: DrillType
        let framing: String?
        let question: String
        let op: String?
        let params: [String: [Int]]?
        let tolerancePct: Double?
        let referencePerUnit: Double?
        let unitParam: String?
        let toleranceFactor: Double?
        let choices: [String]?
        let correctIndex: Int?
        let explanation: String?
    }

    private struct Bank: Decodable {
        let version: Int
        let templates: [Template]
    }

    let templates: [Template]

    init(templatePack: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.templates = try decoder.decode(Bank.self, from: templatePack).templates
    }

    // The three drill types indexed by seed % 3 (matches webapp/drills.py's _TYPES).
    private static let types: [DrillType] = [.mentalMath, .marketSizing, .frameworkRecall]

    /// The drill for `userId` on `date`. Deterministic all day, varies by day and
    /// by user. Type is chosen by seed % 3, then a seeded template of that type.
    func dailyDrill(userId: Int, date: Date) -> Drill {
        let seed = Self.seed(userId: userId, date: date)
        let dtype = Self.types[Int(seed % 3)]
        let candidates = templates.filter { $0.drillType == dtype }
        var chooser = SplitMix64(seed: UInt64(seed))
        let index = Int(chooser.next() % UInt64(candidates.count))
        return generate(template: candidates[index], seed: seed)
    }

    /// Render a template into a wire Drill for `seed`. A fresh SplitMix64(seed)
    /// per call, so param draws are reproducible independent of the template pick.
    func generate(template: Template, seed: UInt32) -> Drill {
        var rng = SplitMix64(seed: UInt64(seed))
        switch template.drillType {
        case .mentalMath:
            let params = Self.drawParams(template.params ?? [:], using: &rng)
            let value = Self.applyOp(template.op ?? "", params)
            let framing = Self.render(template.framing ?? "", params: params, answer: nil)
            let question = Self.render(template.question, params: params, answer: nil)
            let prompt = framing.isEmpty
                ? question
                : "\(framing) \(question)".trimmingCharacters(in: .whitespaces)
            let explanation = Self.render(template.explanation ?? "", params: params, answer: Self.fmtNum(value))
            return Drill(
                key: template.key, drillType: .mentalMath, prompt: prompt, choices: nil,
                answer: DrillAnswer(kind: .numeric, value: value,
                                    tolerancePct: template.tolerancePct, toleranceFactor: nil, correctIndex: nil),
                explanation: explanation, numbers: Self.numbers(in: prompt)
            )

        case .marketSizing:
            let params = Self.drawParams(template.params ?? [:], using: &rng)
            let value = (template.referencePerUnit ?? 0) * Double(params[template.unitParam ?? ""] ?? 0)
            let prompt = Self.render(template.question, params: params, answer: nil)
            let explanation = Self.render(template.explanation ?? "", params: params, answer: Self.commaGroup(value))
            return Drill(
                key: template.key, drillType: .marketSizing, prompt: prompt, choices: nil,
                answer: DrillAnswer(kind: .numeric, value: value,
                                    tolerancePct: nil, toleranceFactor: template.toleranceFactor, correctIndex: nil),
                explanation: explanation, numbers: Self.numbers(in: prompt)
            )

        case .frameworkRecall:
            var choices = template.choices ?? []
            let correct = choices.isEmpty ? "" : choices[template.correctIndex ?? 0]
            choices.shuffle(using: &rng)
            let prompt = template.question
            return Drill(
                key: template.key, drillType: .frameworkRecall, prompt: prompt, choices: choices,
                answer: DrillAnswer(kind: .choice, value: nil, tolerancePct: nil, toleranceFactor: nil,
                                    correctIndex: choices.firstIndex(of: correct) ?? 0),
                explanation: template.explanation ?? "", numbers: Self.numbers(in: prompt)
            )
        }
    }

    // MARK: - Seed

    /// int(sha256("{userId}:{yyyy-MM-dd}").hexdigest()[:8], 16) — the first 4
    /// digest bytes as a big-endian UInt32, identical to the server's seed value.
    static func seed(userId: Int, date: Date) -> UInt32 {
        let input = "\(userId):\(dateFormatter.string(from: date))"
        let digest = Array(SHA256.hash(data: Data(input.utf8)))
        return (UInt32(digest[0]) << 24) | (UInt32(digest[1]) << 16)
             | (UInt32(digest[2]) << 8) | UInt32(digest[3])
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Param draws

    /// Draw each `[lo, hi, step]` inclusive range. Sorted param-key order keeps the
    /// draw sequence stable across launches (Dictionary iteration order is not).
    static func drawParams(_ spec: [String: [Int]], using rng: inout SplitMix64) -> [String: Int] {
        var out: [String: Int] = [:]
        for name in spec.keys.sorted() {
            guard let range = spec[name], range.count == 3 else { continue }
            let lo = range[0], hi = range[1], step = max(range[2], 1)
            let count = (hi - lo) / step + 1
            let pick = count > 0 ? Int(rng.next() % UInt64(count)) : 0
            out[name] = lo + step * pick
        }
        return out
    }

    // MARK: - Op table (ported verbatim from webapp/drills.py's _OPS)

    /// Every answer is recomputable from op + params. Answers CAN be negative
    /// (pct_change with b < a) — that is by design; the grader tolerates it.
    /// cagr_2yr_approx keeps the deliberate linear shortcut, not a true CAGR.
    static func applyOp(_ op: String, _ p: [String: Int]) -> Double {
        func v(_ k: String) -> Double { Double(p[k] ?? 0) }
        switch op {
        case "pct_change":           return (v("b") - v("a")) / v("a") * 100
        case "growth_compound":      return v("a") * pow(1 + v("g") / 100, 2)
        case "breakeven_units":      return v("fixed") / (v("price") - v("vc"))
        case "margin_pct":           return (v("rev") - v("cost")) / v("rev") * 100
        case "markup_price":         return v("cost") * (1 + v("markup") / 100)
        case "market_share_revenue": return v("market") * v("share") / 100
        case "per_capita":           return v("total") / v("pop")
        case "weighted_avg_2":       return (v("v1") * v("w1") + v("v2") * v("w2")) / (v("w1") + v("w2"))
        case "cagr_2yr_approx":      return (v("end") - v("start")) / v("start") / 2 * 100
        case "payback_months":       return v("invest") / v("monthly")
        default:                     return 0
        }
    }

    // MARK: - Rendering

    /// Substitute `{name}` params (integers, comma-free) and `{answer}` into a
    /// template string — mirrors Python's str.format(**params, answer=...).
    static func render(_ template: String, params: [String: Int], answer: String?) -> String {
        var out = template
        for (name, value) in params {
            out = out.replacingOccurrences(of: "{\(name)}", with: String(value))
        }
        if let answer = answer {
            out = out.replacingOccurrences(of: "{answer}", with: answer)
        }
        return out
    }

    /// Human-readable answer for the explanation string (2 dp, trailing .0 dropped).
    static func fmtNum(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// Comma-grouped integer, mirroring Python f"{value:,}" for market-sizing answers.
    static func commaGroup(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    // MARK: - Numbers

    private static let numberRegex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)

    /// Every numeric literal in `text`, verbatim as rendered — mirrors Python's
    /// _NUM_RE.findall. The on-device FM validator matches its dressing against these.
    static func numbers(in text: String) -> [String] {
        let ns = text as NSString
        return numberRegex
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }
}
