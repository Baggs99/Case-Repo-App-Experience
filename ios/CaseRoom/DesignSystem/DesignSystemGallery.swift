/*
 * Purpose: DEBUG-only visual gallery of every DesignSystem component in one theme
 *          (light by default, dark via the -DSGalleryDark launch arg) — F0's
 *          screenshot evidence and later phases' visual reference.
 * Inputs: launch arg -DSGalleryDark; PreviewFixtures.
 * Outputs: DesignSystemGallery.
 * Run: launched via `-DSGallery [-DSGalleryDark]`; captured with `simctl io screenshot`.
 */

#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    private let palette: DSPalette =
        ProcessInfo.processInfo.arguments.contains("-DSGalleryDark") ? .dark : .light
    private var scrollAnchor: UnitPoint {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-DSGalleryBottom") { return .bottom }
        if args.contains("-DSGalleryMid") { return .center }
        return .top
    }
    @State private var rating = 3
    @State private var tab: DSTab = .home
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            DSBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    HStack { WordmarkChip(); Spacer(); AvatarPill(initials: "AO") }
                    section("PALETTE") { swatches }
                    section("TYPE SCALE") { typeSamples }
                    section("GLASS") { glassSamples }
                    section("THE MARK") {
                        HStack(spacing: 28) {
                            StaircaseMarkView().frame(width: 48, height: 40)
                            StaircaseMarkView(animated: true).frame(width: 48, height: 40)
                            BlinkDot(diameter: 8)
                            Spacer()
                        }
                    }
                    section("STEPPED TIMELINE") { SteppedTimeline(firms: PreviewFixtures.phone.timeline) }
                    section("SCORE CELLS") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("recap 1–5 (interactive)").dsText(.meta).foregroundStyle(palette.muted)
                            ScoreCells(count: 5, value: rating, size: .large, interactive: true) { rating = $0 }
                            Text("rubric 1–10 · 24pt").dsText(.meta).foregroundStyle(palette.muted)
                            ScoreCells(count: 10, value: 7, size: .medium)
                            Text("live 1–12 · 16pt").dsText(.meta).foregroundStyle(palette.muted)
                            ScoreCells(count: 12, value: 5, size: .small)
                        }
                    }
                    section("TOAST") {
                        Button("Show toast") { toast = "Copied  K7Q-4TN" }
                            .buttonStyle(DSPressStyle())
                            .dsText(.rowTitle).foregroundStyle(palette.link)
                    }
                    Color.clear.frame(height: 96)   // room behind the tab bar
                }
                .padding(24)
            }
            .defaultScrollAnchor(scrollAnchor)
            .dsHeaderFade()

            DSTabBar(selection: $tab,
                     maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 560 : nil)
                .padding(.bottom, 12)
        }
        .dsTheme(palette)
        .dsToast(item: $toast)
        .background(palette.page.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(palette.isDark ? "DESIGN SYSTEM · DARK TAKEOVER" : "DESIGN SYSTEM · LIGHT")
                .dsText(.kicker).foregroundStyle(palette.green)
            Text("myCase F0").dsText(.h1Tab).foregroundStyle(palette.ink)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).dsText(.kicker).foregroundStyle(palette.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel()
    }

    private var swatches: some View {
        let items: [(String, Color)] = [
            ("page", palette.page), ("ink", palette.ink), ("muted", palette.muted),
            ("faint", palette.faint), ("hairline", palette.hairline),
            ("surface", palette.surface), ("green", palette.green), ("link", palette.link),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.hairline))
                    Text(name).dsText(.meta).foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var typeSamples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fifty-eight days.").dsText(.h1Tab).foregroundStyle(palette.ink)
            Text("Morning, Amara.").dsText(.cardTitle).foregroundStyle(palette.ink)
            Text("YOU'VE BEEN ASKED TO INTERVIEW").dsText(.kicker).foregroundStyle(palette.green)
            Text("Structure held. The quant went soft in the middle.")
                .dsText(.serif(14.5, italic: true)).foregroundStyle(palette.muted)
            Text("19:00").dsText(.timerLarge).tabularNumbers().foregroundStyle(palette.ink)
        }
    }

    private var glassSamples: some View {
        HStack(spacing: 12) {
            Text("Panel").dsText(.rowTitle).foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity).padding(20).glassPanel()
            Text("Chip").dsText(.rowTitle).foregroundStyle(palette.ink)
                .padding(.horizontal, 16).padding(.vertical, 10).glassChip()
        }
    }
}

#Preview("Gallery — Light") { DesignSystemGallery() }
#endif
