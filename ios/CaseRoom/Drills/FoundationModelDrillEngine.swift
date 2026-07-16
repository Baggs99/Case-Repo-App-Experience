/*
 * Purpose: On-device Foundation Models drill engine (iOS 26+) — takes the
 *          deterministic LocalDrillGenerator drill and asks the system model to
 *          restyle ONLY the prompt, shipping the rewrite only if it is validated.
 * Inputs: a LocalDrillGenerator (built from the cached pack), a user id, a date
 *         provider; the on-device SystemLanguageModel at generation time.
 * Outputs: a Drill whose answer/grading/explanation are untouched; prompt is the
 *          validated FM dressing when valid, else the plain deterministic prompt.
 * Run: try await FoundationModelDrillEngine(generator: gen, userId: 1).dailyDrill()
 *
 * The ONLY file that touches FoundationModels; whole file is @available(iOS 26.0, *).
 * FM generation cannot run in the simulator/tests — the deterministic core, the
 * validator, and provider selection are the test surface; the live path is a device
 * check. The engine NEVER changes answers: dressingIsValid gates the rewrite so a
 * hallucinated/reformatted number falls back to the plain prompt.
 */

import Foundation
import FoundationModels

@available(iOS 26.0, *)
final class FoundationModelDrillEngine: DrillEngine {
    private let generator: LocalDrillGenerator
    private let userId: Int
    private let dateProvider: () -> Date

    init(generator: LocalDrillGenerator, userId: Int, dateProvider: @escaping () -> Date = { Date() }) {
        self.generator = generator
        self.userId = userId
        self.dateProvider = dateProvider
    }

    var sourceLabel: String { "on_device" }

    /// True when the on-device model is ready to generate. Read by the provider's
    /// default probe (behind its own #available check).
    static func isModelAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Every string in `numbers` must appear verbatim in `dressed`, else the
    /// dressing is rejected and the plain prompt ships. Substring match (mirrors
    /// the server contract): a reformatted "1,200" fails a "1200" requirement.
    static func dressingIsValid(_ dressed: String, numbers: [String]) -> Bool {
        numbers.allSatisfy { dressed.contains($0) }
    }

    func dailyDrill() async throws -> Drill {
        guard case .available = SystemLanguageModel.default.availability else {
            throw DrillEngineError.unavailable
        }
        let base = generator.dailyDrill(userId: userId, date: dateProvider())

        let session = LanguageModelSession()
        let numbersList = base.numbers.joined(separator: ", ")
        let instruction = """
        Rewrite this case-interview drill prompt in a fresh voice. Keep EVERY number \
        exactly as given, keep the question's meaning, ≤2 sentences + the question. \
        Numbers: \(numbersList) Prompt: \(base.prompt)
        """

        do {
            let response = try await session.respond(to: instruction, generating: DrillDressing.self)
            let dressed = response.content.prompt
            if Self.dressingIsValid(dressed, numbers: base.numbers) {
                // Prompt only — answer, explanation, choices, numbers all preserved.
                return Drill(
                    key: base.key, drillType: base.drillType, prompt: dressed, choices: base.choices,
                    answer: base.answer, explanation: base.explanation, numbers: base.numbers
                )
            }
        } catch {
            // Any generation failure falls through to the plain deterministic prompt.
        }
        return base
    }
}

@available(iOS 26.0, *)
@Generable
struct DrillDressing {
    @Guide(description: "The rewritten drill prompt: ≤2 sentences plus the question, every number kept exactly as given.")
    var prompt: String
}
