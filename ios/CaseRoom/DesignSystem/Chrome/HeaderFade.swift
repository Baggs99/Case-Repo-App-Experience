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
            LinearGradient(
                colors: [palette.page, palette.page.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 34)
            .allowsHitTesting(false)
        }
    }
}
