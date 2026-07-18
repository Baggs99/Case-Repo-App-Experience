/*
 * Purpose: The myCase color token layer — the ONLY place hex literals live.
 *          Two palettes: .light (default, every tab) and .dark (session-takeover
 *          theme, NOT iOS dark mode), threaded through the \.dsPalette environment.
 * Inputs: none.
 * Outputs: DSPalette, Color(hex:), \.dsPalette environment, View.dsTheme(_:).
 * Run: imported by every DesignSystem component; screens read \.dsPalette.
 */

import SwiftUI

/// The design palette. Every color in the app resolves from here (F0 rule: no
/// hex literals outside this file). `.light` is the default for every tab;
/// `.dark` is the session-takeover theme applied per-screen, not iOS dark mode.
struct DSPalette: Equatable {
    let page: Color
    let ink: Color
    let onInk: Color        // chalk text ON an ink fill (toast, CASE circle, avatar)
    let muted: Color        // owner-locked #515A66 in light
    let faint: Color
    let hairline: Color
    let hairlineSoft: Color
    let surface: Color
    let pdfBackdrop: Color  // PDF-mode paper-grey behind the white page (T5) — a shade darker than `page`, not covered by page/surface/hairline
    let green: Color        // scarce accent
    let link: Color         // cobalt
    let isDark: Bool

    static let light = DSPalette(
        page: Color(hex: 0xEFF2F6),
        ink: Color(hex: 0x0D1C31),
        onInk: Color(hex: 0xF3F5F8),
        muted: Color(hex: 0x515A66),
        faint: Color(hex: 0xA9B4C4),
        hairline: Color(hex: 0xC9D2DF),
        hairlineSoft: Color(hex: 0xDDE3EB),
        surface: Color(hex: 0xFFFFFF),
        pdfBackdrop: Color(hex: 0xE7EBF1),   // canvas PDF-mode paper-grey (Tablet 1a §7-1a)
        green: Color(hex: 0x1B9A5F),
        link: Color(hex: 0x2E56C0),
        isDark: false
    )

    static let dark = DSPalette(
        page: Color(hex: 0x081222),
        ink: Color(hex: 0xE9EEF5),
        onInk: Color(hex: 0x081222),
        muted: Color(hex: 0x7C8CA8),
        faint: Color(hex: 0x3D5075),
        hairline: Color(hex: 0x24365A),
        hairlineSoft: Color(hex: 0x24365A),
        surface: Color(hex: 0x101E36),
        pdfBackdrop: Color(hex: 0x0C1729),   // dark-takeover analog (a step off `page`); the console overrides to .light so it seldom shows
        green: Color(hex: 0x2FC07E),
        link: Color(hex: 0x2E56C0),
        isDark: true
    )
}

extension Color {
    /// 0xRRGGBB hex. Confined to the token layer (F0 no-hex-elsewhere rule).
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// The fixed ink used for glass shadows and sheet scrims — theme-independent
    /// (a shadow/scrim stays navy even under the dark takeover, where `ink`
    /// flips to chalk). Keeps every hex literal inside this token file.
    static let dsShadowInk = Color(hex: 0x0D1C31)
}

private struct DSPaletteKey: EnvironmentKey {
    static let defaultValue = DSPalette.light
}

extension EnvironmentValues {
    var dsPalette: DSPalette {
        get { self[DSPaletteKey.self] }
        set { self[DSPaletteKey.self] = newValue }
    }
}

extension View {
    /// Scope a subtree to a palette (default .light; .dark = session takeover).
    func dsTheme(_ palette: DSPalette) -> some View { environment(\.dsPalette, palette) }
}
