/*
 * Purpose: The onboarding passcode entry — a row of 6 dots (filled ink / empty
 *          hairline ring) over a 3×4 glass keypad (1-9, blank, 0, ⌫). Appends
 *          digits to a bound `code` capped at 6 and fires onComplete the moment
 *          the sixth digit lands (auto-advance). Distinct from GauntletKeypad:
 *          NO `.` and NO `±` — digits only.
 * Inputs: $code (digits only, ≤6); onComplete callback; \.dsPalette.
 * Outputs: mutates the bound code; calls onComplete on the 5→6 transition.
 * Run: OnboardingPasscodeView binds it to vm.code with onComplete → submitCode.
 */

import SwiftUI

struct PasscodeKeypad: View {
    @Environment(\.dsPalette) private var palette
    @Binding var code: String
    var onComplete: () -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]

    /// The pure key-application rule (digits-only, cap 6, ⌫ deletes last),
    /// factored out so the append/delete/complete logic is unit-testable
    /// without hosting the View. `completed` is true only on the 5→6 transition.
    static func apply(key: String, to code: String) -> (code: String, completed: Bool) {
        if key == "⌫" {
            return (code.isEmpty ? code : String(code.dropLast()), false)
        }
        guard code.count < 6, key.count == 1, key.first!.isNumber else { return (code, false) }
        let next = code + key
        return (next, next.count == 6)
    }

    var body: some View {
        VStack(spacing: 22) {
            dots
            VStack(spacing: 9) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 9) {
                        ForEach(row, id: \.self) { key in keyButton(key) }
                    }
                }
            }
        }
    }

    // MARK: - Dots

    private var dots: some View {
        HStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { index in
                Group {
                    if index < code.count {
                        Circle().fill(palette.ink)
                    } else {
                        Circle().stroke(palette.hairline, lineWidth: 1.5)
                    }
                }
                .frame(width: 13, height: 13)
            }
        }
        .animation(DSMotion.hoverCurve, value: code.count)
    }

    // MARK: - Keys

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            // Layout placeholder in the bottom-left slot — no key there.
            Color.clear.frame(maxWidth: .infinity).frame(height: 54)
        } else {
            Button { press(key) } label: {
                Text(key)
                    // The ⌫ glyph isn't in Archivo — resolve it via the system
                    // font (a sanctioned key, not a decorative icon), mirroring
                    // GauntletKeypad.
                    .font(key == "⌫" ? .system(size: 22, weight: .semibold) : .archivo(22, weight: 700))
                    .tabularNumbers()
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .glassKey()
            }
            .buttonStyle(DSPressStyle())
            .accessibilityLabel(key == "⌫" ? "Delete" : key)
        }
    }

    private func press(_ key: String) {
        let result = Self.apply(key: key, to: code)
        code = result.code
        if result.completed { onComplete() }
    }
}

#if DEBUG
private struct PasscodeKeypadPreview: View {
    @State private var code = "12"
    var body: some View {
        ZStack {
            DSBackground()
            PasscodeKeypad(code: $code, onComplete: {})
                .padding(24)
        }
    }
}

#Preview { PasscodeKeypadPreview() }
#endif
