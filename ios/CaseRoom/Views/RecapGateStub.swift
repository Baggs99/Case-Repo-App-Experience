/*
 * Purpose: MARK: F3 INTERIM — F5 replaces this with the real recap report +
 *          close-out sheet (canvas 6b) at merge. A minimal token-styled
 *          placeholder so `.recap(sessionID)` compiles and is
 *          screenshot-provable this wave: a `‹ Back` pill + the session id +
 *          a note. No rubric bars, no PDF, no close-out gate — that is F5's.
 * Inputs: sessionID (the gated/tapped recap's session id).
 * Outputs: none (Back pops router.casePath by one).
 * Run: pushed via `NavigationStack(path: $router.casePath)`'s
 *      `.navigationDestination(for: AppRoute.self)` for `.recap(id)` — see
 *      RootShell's `// MARK: F3` block.
 */

import SwiftUI

struct RecapGateStub: View {
    let sessionID: Int
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            backButton
            Text("Recap #\(sessionID)")
                .dsText(.serif(20, italic: true, weight: 600))
                .foregroundStyle(palette.ink)
            Text("Recap screens land with F5.")
                .dsText(.meta)
                .foregroundStyle(palette.muted)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var backButton: some View {
        Button {
            if !AppRouter.shared.casePath.isEmpty {
                AppRouter.shared.casePath.removeLast()
            }
        } label: {
            BackPill(label: "Back")
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground(); RecapGateStub(sessionID: 102) }
}
#endif
