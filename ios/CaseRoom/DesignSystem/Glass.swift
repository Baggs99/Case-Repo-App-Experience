/*
 * Purpose: The glass chrome layer — panels, chips, sheets — reproducing the §1
 *          recipes over .ultraThinMaterial (the JUDGMENT call: hand-built for
 *          canvas fidelity vs iOS 26 .glassEffect, which the deployment target
 *          and owner-locked recipe rule out). Includes the dark-takeover recipe,
 *          a scrim, the rise transition, and a solid-white fallback under Reduce
 *          Transparency (the body.solid analog).
 * Inputs: \.dsPalette, \.accessibilityReduceTransparency.
 * Outputs: .glassPanel/.glassChip/.glassSheet/.glassKey/.glassChipFlat, DSScrim, AnyTransition.dsRise.
 * Run: `SomeView().glassPanel()`; sheets `.transition(.dsRise)`.
 */

import SwiftUI

// `.key` is the flat secondary surface (Canon §1 line 29): a solid white .55 fill
// over the material blur (NOT the panel's .66→.4 gradient) with only the top inset
// highlight — used for keys/cells (radius 16) and secondary chips/buttons (capsule).
enum GlassKind { case panel, chip, sheet, key }

/// The glass surface engine. Layers the §1 recipe: blur (ultraThinMaterial),
/// the 135° white gradient (or the dark rgba fill), a white hairline border, and
/// a top inset highlight. Under Reduce Transparency it collapses to a solid fill.
struct GlassSurface<S: InsettableShape>: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let kind: GlassKind

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(palette.surface)                       // --gbg:#FFFFFF; --gblur:0
            } else if palette.isDark {
                shape.fill(.ultraThinMaterial)
                shape.fill(palette.surface.opacity(0.6))          // rgba(16,30,54,.6)
            } else if kind == .key {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.55))             // flat solid fill (no gradient)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(gbg)                                   // white gradient .66 → .4
            }
        }
        .overlay(shape.strokeBorder(border, lineWidth: 1))
        .overlay(topInsetHighlight)                               // inset 0 1.5px 0 rgba(255,255,255,.85)
        .overlay(bottomHighlight)                                 // key has top-only; others also bottom
        .compositingGroup()
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var gbg: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.66), .white.opacity(0.40)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var border: Color {
        palette.isDark ? palette.ink.opacity(0.14) : .white.opacity(kind == .chip || kind == .key ? 0.75 : 0.72)
    }

    private var topInsetHighlight: some View {
        shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(palette.isDark ? 0.12 : 0.85), .clear],
                           startPoint: .top, endPoint: .center),
            lineWidth: 1.5)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// The bottom inset highlight — omitted for `.key` (flat: top highlight only).
    @ViewBuilder private var bottomHighlight: some View {
        if kind != .key {
            shape.strokeBorder(
                LinearGradient(colors: [.clear, .white.opacity(palette.isDark ? 0.06 : 0.3)],
                               startPoint: .center, endPoint: .bottom),
                lineWidth: 1)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    private var shadowColor: Color {
        palette.isDark ? .black.opacity(0.35) : Color.dsShadowInk.opacity(kind == .chip || kind == .key ? 0.07 : 0.16)
    }
    private var shadowRadius: CGFloat { (kind == .chip || kind == .key) ? 8 : (kind == .sheet ? 30 : 22) }
    private var shadowY: CGFloat { (kind == .chip || kind == .key) ? 2 : (kind == .sheet ? 24 : 18) }
}

extension View {
    /// Glass card/panel. Corners 26–30 per §1 (default 28).
    func glassPanel(cornerRadius: CGFloat = 28) -> some View {
        background(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), kind: .panel))
    }
    /// Glass chip/pill/tab bar (capsule).
    func glassChip() -> some View {
        background(GlassSurface(shape: Capsule(), kind: .chip))
    }
    /// Glass sheet. Corners 32–34 per §1 (default 32).
    func glassSheet(cornerRadius: CGFloat = 32) -> some View {
        background(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), kind: .sheet))
    }
    /// Flat key/cell glass (§1 line 29): solid white .55 fill, top-only highlight. Radius 16.
    func glassKey(cornerRadius: CGFloat = 16) -> some View {
        background(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), kind: .key))
    }
    /// Flat secondary chip/button glass (§1 line 29): the `.key` recipe on a capsule.
    func glassChipFlat() -> some View {
        background(GlassSurface(shape: Capsule(), kind: .key))
    }
}

/// Scrim under sheets: rgba(13,28,49,.34) + blur(5). Solid-ish under Reduce Transparency.
struct DSScrim: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial)
            }
            Color.dsShadowInk.opacity(reduceTransparency ? 0.5 : 0.34)
        }
        .ignoresSafeArea()
    }
}

extension AnyTransition {
    /// Sheet rise: 16px up + fade (pair with DSMotion.sheetCurve at the call site).
    static var dsRise: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
}
