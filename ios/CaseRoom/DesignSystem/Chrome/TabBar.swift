/*
 * Purpose: The floating 5-slot glass tab bar with the raised center CASE circle.
 *          Active states per §1: selected label → ink weight-800 (HOME adds a 4px
 *          green dot; CASE-active adds a 2px green ring on the circle); inactive
 *          → muted. Content scrolls behind it.
 * Inputs: selection binding, onSelect, \.dsPalette.
 * Outputs: DSTab, DSTabBar.
 * Run: `DSTabBar(selection: $tab) { tab = $0 }` pinned to the bottom.
 */

import SwiftUI

enum DSTab: Hashable, CaseIterable {
    case home, library, caseTab, community, drills

    var label: String {
        switch self {
        case .home: return "HOME"
        case .library: return "LIBRARY"
        case .caseTab: return "CASE"
        case .community: return "COMMUNITY"
        case .drills: return "DRILLS"
        }
    }
}

struct DSTabBar: View {
    @Binding var selection: DSTab
    var onSelect: (DSTab) -> Void = { _ in }
    /// Cap the bar width. nil = full-width phone (left/right 12); pass 560 for the
    /// §7 tablet ("560px wide, centered") so F2 doesn't have to modify this primitive.
    var maxWidth: CGFloat? = nil
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            slot(.home)
            slot(.library)
            caseSlot
            slot(.community)
            slot(.drills)
        }
        .frame(height: 64)
        .padding(.horizontal, 8)
        .frame(maxWidth: maxWidth ?? .infinity)
        .glassChip()
        // Floating-bar shadow per canon (0 10px 26px rgba(13,28,49,.14)).
        .shadow(color: Color.dsShadowInk.opacity(0.14), radius: 13, x: 0, y: 5)
        .frame(maxWidth: .infinity)   // center the (optionally capped) bar
        .padding(.horizontal, 12)
    }

    private func slot(_ tab: DSTab) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Text(tab.label)
                    .font(.archivo(9, weight: active ? 800 : 600))
                    .tracking(1.08)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(active ? palette.ink : palette.muted)
                Circle()
                    .fill(tab == .home && active ? palette.green : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
    }

    private var caseSlot: some View {
        let active = selection == .caseTab
        return Button {
            selection = .caseTab
            onSelect(.caseTab)
        } label: {
            ZStack {
                // The CASE circle is fixed navy in both themes (canvas hardcodes
                // #0D1C31); its mark is the canvas g22 gradient chalk→bright-green.
                Circle()
                    .fill(DSPalette.light.ink)
                    .frame(width: 56, height: 56)
                    .overlay(active ? Circle().strokeBorder(DSPalette.dark.green, lineWidth: 2) : nil)
                    .shadow(color: Color.dsShadowInk.opacity(0.3), radius: 12, x: 0, y: 8)
                StaircaseMarkView(lowColor: DSPalette.light.onInk, highColor: DSPalette.dark.green)
                    .frame(width: 23, height: 19)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -13)
        }
        .buttonStyle(DSPressStyle())
    }
}
