/*
 * Purpose: Motion constants and shared motion components — the §1 rise/draw/blink
 *          curves, the press-scale button style, and the live blink dot.
 *          Nothing bounces (no springs).
 * Inputs: \.dsPalette.
 * Outputs: DSMotion, DSPressStyle, BlinkDot. (AnyTransition.dsRise lives in Glass.swift.)
 * Run: `.animation(DSMotion.riseCurve, value: x)`; `.buttonStyle(DSPressStyle())`.
 */

import SwiftUI

enum DSMotion {
    /// 420ms content rise, cubic-bezier(0.22,1,0.36,1).
    static let riseCurve  = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    /// 320ms sheet rise.
    static let sheetCurve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.32)
    /// 160ms hover/press-in lift.
    static let hoverCurve = Animation.easeOut(duration: 0.16)
    /// 900ms mark trim-draw.
    static let drawCurve  = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.9)
    /// 120–150ms stagger between rising items.
    static let stagger: Double = 0.13
    /// Press feedback scale.
    static let pressScale: CGFloat = 0.96
    /// 1.1s live blink (opacity 1 → .2 → 1).
    static let blink = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
}

/// Press feedback: scale to .96, no bounce.
struct DSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DSMotion.pressScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A small dot that pulses 1 → .2 for "live".
struct BlinkDot: View {
    @Environment(\.dsPalette) private var palette
    var diameter: CGFloat = 6
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(palette.green)
            .frame(width: diameter, height: diameter)
            .opacity(dim ? 0.2 : 1)
            .onAppear { withAnimation(DSMotion.blink) { dim = true } }
    }
}
