/*
 * Purpose: Transitional COMMUNITY tab placeholder — F8 replaces it (canvas 6a).
 * Inputs: \.dsPalette.
 * Outputs: none.
 * Run: rendered by RootShell for DSTab.community.
 */

import SwiftUI

struct CommunityTabStub: View {
    @Environment(\.dsPalette) private var palette
    var body: some View {
        VStack(spacing: 8) {
            Text("Community").dsText(.h1Tab).foregroundStyle(palette.ink)
            Text("Arrives in a later phase.").dsText(.meta).foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
