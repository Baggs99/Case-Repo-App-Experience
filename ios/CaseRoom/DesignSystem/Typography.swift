/*
 * Purpose: myCase type system — registers the bundled variable fonts and exposes
 *          weight-parameterized helpers plus the §1 type scale. Weight selection
 *          uses SwiftUI's family + weight-trait resolution (Font.custom + .weight),
 *          verified via a CoreText probe to pick the correct named instance for
 *          Archivo (Regular/SemiBold/Bold/ExtraBold) and Source Serif 4 (+italic).
 * Inputs: bundled Archivo / Source Serif 4 variable TTFs.
 * Outputs: DSFonts.register(), Font.archivo/.serifVoice, DSTextStyle, .dsText, .tabularNumbers.
 * Run: DSFonts.register() at launch; screens call Font.archivo(...)/.serifVoice(...).
 */

import SwiftUI
import CoreText

enum DSFonts {
    static let archivoFamily = "Archivo"
    static let serifFamily = "Source Serif 4"

    /// Idempotent programmatic registration. UIAppFonts (info.properties) is the
    /// primary path for the app; this belt-and-suspenders call also loads the
    /// fonts into the host-less unit-test process (Fonts are a test-target resource).
    static func register() {
        guard !hasRegistered else { return }
        hasRegistered = true
        let names = ["Archivo-Variable", "SourceSerif4-Variable", "SourceSerif4-Italic-Variable"]
        for name in names {
            guard let url = Bundle(for: DSFontsMarker.self).url(forResource: name, withExtension: "ttf")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Map a numeric design weight (400–800) to the SwiftUI weight trait that
    /// Core Text resolves to the matching named instance in the variable font.
    static func weight(_ w: CGFloat) -> Font.Weight {
        switch w {
        case ..<450: return .regular    // 400 → ArchivoRoman-Regular
        case ..<550: return .medium     // 500 → Medium
        case ..<650: return .semibold   // 600 → SemiBold
        case ..<750: return .bold       // 700 → Bold
        default:     return .heavy       // 800 → ExtraBold
        }
    }

    private static var hasRegistered = false
}

final class DSFontsMarker {}

extension Font {
    static func archivo(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        DSFonts.register()
        return Font.custom(DSFonts.archivoFamily, fixedSize: size).weight(DSFonts.weight(weight))
    }

    static func serifVoice(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        DSFonts.register()
        var font = Font.custom(DSFonts.serifFamily, fixedSize: size).weight(DSFonts.weight(weight))
        if italic { font = font.italic() }
        return font
    }
}

/// A type-scale entry: font + letter tracking (points) + line spacing.
/// SwiftUI tracking is in points, so tracking = em × size.
struct DSTextStyle {
    let font: Font
    let tracking: CGFloat
    let lineSpacing: CGFloat

    // §1 phone type scale.
    static let h1Tab           = DSTextStyle(font: .archivo(28, weight: 800), tracking: -0.84, lineSpacing: 0)  // -.03em
    static let takeoverDisplay = DSTextStyle(font: .archivo(32, weight: 800), tracking: -1.12, lineSpacing: 0)  // -.035em
    static let cardTitle       = DSTextStyle(font: .archivo(20, weight: 700), tracking: -0.2,  lineSpacing: 0)
    static let rowTitle        = DSTextStyle(font: .archivo(14, weight: 600), tracking: 0,     lineSpacing: 0)
    static let rowTitleStrong  = DSTextStyle(font: .archivo(14.5, weight: 700), tracking: 0,   lineSpacing: 0)
    static let kicker          = DSTextStyle(font: .archivo(10, weight: 600), tracking: 1.6,   lineSpacing: 0)  // .16em caps
    static let meta            = DSTextStyle(font: .archivo(11.5, weight: 400), tracking: 0,   lineSpacing: 0)
    static let timerLarge      = DSTextStyle(font: .archivo(34, weight: 700), tracking: 0,     lineSpacing: 0)

    static func serif(_ size: CGFloat, italic: Bool = false, weight: CGFloat = 400) -> DSTextStyle {
        DSTextStyle(font: .serifVoice(size, weight: weight, italic: italic), tracking: 0, lineSpacing: size * 0.5)
    }
}

extension View {
    /// Apply a DSTextStyle (font + tracking + line spacing; color left to caller).
    func dsText(_ style: DSTextStyle) -> some View {
        self.font(style.font).tracking(style.tracking).lineSpacing(style.lineSpacing)
    }

    /// Tabular numerals — always on for timers/scores.
    func tabularNumbers() -> some View { self.monospacedDigit() }
}
