/*
 * Purpose: Transitional DRILLS tab placeholder — a later phase replaces it.
 * Inputs: \.dsPalette.
 * Outputs: none.
 * Run: rendered by RootShell for DSTab.drills.
 */

import SwiftUI

struct DrillsTabStub: View {
    @Environment(\.dsPalette) private var palette
    var body: some View {
        VStack(spacing: 8) {
            Text("Drills").dsText(.h1Tab).foregroundStyle(palette.ink)
            Text("Arrives in a later phase.").dsText(.meta).foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
