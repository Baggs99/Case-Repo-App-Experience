/*
 * Purpose: The gauntlet run's numeric keypad (canvas 5b run, numeric slot) — a
 *          glass keypad (0-9, `.`, `±` sign toggle, `⌫` delete) + a value
 *          display + a "Next" advance capsule. Reproduces DrillViewModel's
 *          numeric-input semantics: a raw input String parsed via `Double(_:)`
 *          with an out-of-band `isNegative` sign toggle (the decimal pad has no
 *          minus key), applied at read time — never mutating parseability.
 * Inputs: bindings to the owning VM's `input`/`isNegative` (single source of
 *         truth so the VM captures the value on advance); a `canAdvance` gate +
 *         an `onAdvance` callback.
 * Outputs: mutates the bound input/sign; the signed Double is read via the
 *          static `signedValue(input:isNegative:)` helper (VM + display share it).
 * Run: GauntletKeypad(input: $vm.numericInput, isNegative: $vm.isNegative,
 *                     canAdvance: vm.canAdvance, onAdvance: { ... })
 */

import SwiftUI

struct GauntletKeypad: View {
    @Environment(\.dsPalette) private var palette
    @Binding var input: String
    @Binding var isNegative: Bool
    let canAdvance: Bool
    let onAdvance: () -> Void

    // 3-col digit grid; the sign toggle rides beside the value display (the
    // DrillView numeric pattern: ± is a distinct sign toggle, not a digit key).
    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]

    /// The single parse — DrillViewModel's `Double(input).map { isNegative ? -$0 : $0 }`
    /// reproduced verbatim. The VM and the display read the value through here.
    static func signedValue(input: String, isNegative: Bool) -> Double? {
        Double(input).map { isNegative ? -$0 : $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            displayRow
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
            nextButton
        }
    }

    // MARK: - Value display + sign toggle

    private var displayRow: some View {
        HStack(spacing: 12) {
            Button { isNegative.toggle() } label: {
                Text("±")
                    .font(.archivo(21, weight: 700))
                    .foregroundStyle(isNegative ? palette.onInk : palette.ink)
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityLabel("Toggle negative")
            // The ink capsule (active) sits in front of the glass (inactive) —
            // later `.background`s stack further back, so glass is the base.
            .background(Capsule().fill(isNegative ? palette.ink : Color.clear))
            .glassChipFlat()

            Text(displayText)
                .font(.archivo(30, weight: 800)).tracking(-0.02 * 30).tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    private var displayText: String {
        let base = input.isEmpty ? "0" : input
        return (isNegative ? "−" : "") + base
    }

    // MARK: - Keys

    private func keyButton(_ key: String) -> some View {
        Button { press(key) } label: {
            Text(key)
                // The ⌫ glyph isn't in Archivo — let it resolve via the system
                // font so it renders (a sanctioned key per the run spec, not a
                // decorative icon).
                .font(key == "⌫" ? .system(size: 22, weight: .semibold) : .archivo(22, weight: 700))
                .tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .glassKey()
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(key == "⌫" ? "Delete" : key)
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !input.isEmpty { input.removeLast() }
        case ".":
            if input.isEmpty { input = "0." } else if !input.contains(".") { input.append(".") }
        default:                                  // a digit
            if input == "0" { input = key } else { input.append(key) }   // no "007"
        }
    }

    // MARK: - Next

    private var nextButton: some View {
        Button { onAdvance() } label: {
            Text("Next")
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
        .opacity(canAdvance ? 1 : 0.4)
        .disabled(!canAdvance)
    }
}

#if DEBUG
private struct GauntletKeypadPreview: View {
    @State private var input = "17"
    @State private var isNegative = false
    var body: some View {
        ZStack {
            DSBackground()
            GauntletKeypad(input: $input, isNegative: $isNegative,
                           canAdvance: Double(input) != nil, onAdvance: {})
                .padding(24)
        }
    }
}

#Preview { GauntletKeypadPreview() }
#endif
