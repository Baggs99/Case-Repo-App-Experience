/*
 * Purpose: The page backdrop glass needs behind it — the page fill, 1–2 faint
 *          radial tint blobs (green/cobalt, low alpha) and one giant faint
 *          staircase bleeding off-canvas.
 * Inputs: \.dsPalette.
 * Outputs: DSBackground (drop behind any screen).
 * Run: `ZStack { DSBackground(); content }`.
 */

import SwiftUI

struct DSBackground: View {
    @Environment(\.dsPalette) private var palette

    var body: some View {
        // The flexible page Color drives the layout size (== the screen); the
        // fixed-size blobs and the giant staircase are a clipped overlay so they
        // bleed off-canvas without widening the layout of sibling content.
        palette.page
            .overlay {
                ZStack {
                    RadialGradient(colors: [palette.green.opacity(0.10), .clear],
                                   center: .center, startRadius: 0, endRadius: 220)
                        .frame(width: 380, height: 380)
                        .offset(x: -120, y: -260)

                    RadialGradient(colors: [palette.link.opacity(0.09), .clear],
                                   center: .center, startRadius: 0, endRadius: 210)
                        .frame(width: 360, height: 360)
                        .offset(x: 150, y: 240)

                    StaircaseMark()
                        .stroke(palette.hairline.opacity(0.5), lineWidth: 0.6)
                        .frame(width: 480, height: 400)
                        .offset(x: 150, y: -120)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}
