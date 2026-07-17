/*
 * Purpose: The 34px header scroll-fade — page color → transparent over the top of
 *          a scroll container so content fades under the H1 instead of hard-clipping.
 * Inputs: \.dsPalette.
 * Outputs: View.dsHeaderFade().
 * Run: `ScrollView { … }.dsHeaderFade()`.
 */

import SwiftUI

extension View {
    func dsHeaderFade() -> some View { modifier(DSHeaderFade()) }
}

private struct DSHeaderFade: ViewModifier {
    @Environment(\.dsPalette) private var palette

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            // Canvas: linear-gradient(180deg, page 22%, transparent) — solid for
            // the first 22%, then fade out.
            LinearGradient(
                stops: [
                    .init(color: palette.page, location: 0),
                    .init(color: palette.page, location: 0.22),
                    .init(color: palette.page.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 34)
            .allowsHitTesting(false)
        }
    }
}
