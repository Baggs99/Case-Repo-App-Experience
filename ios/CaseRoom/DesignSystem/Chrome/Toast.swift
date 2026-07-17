/*
 * Purpose: The toast capsule (ink .94 fill / chalk text) and a .dsToast overlay
 *          modifier that rises in above the tab bar and auto-dismisses (~2.4s).
 * Inputs: text / a bound optional String, \.dsPalette.
 * Outputs: DSToast, View.dsToast(item:).
 * Run: `.dsToast(item: $toast)` where toast is `@State private var toast: String?`.
 */

import SwiftUI

struct DSToast: View {
    let text: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        Text(text)
            .dsText(.rowTitle)
            .foregroundStyle(palette.onInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(palette.ink.opacity(0.94)))
            .shadow(color: Color.dsShadowInk.opacity(0.3), radius: 13, x: 0, y: 10)
    }
}

extension View {
    func dsToast(item: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = item.wrappedValue {
                DSToast(text: text)
                    .padding(.bottom, 92)
                    .transition(.dsRise)
                    .task(id: text) {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation(DSMotion.sheetCurve) { item.wrappedValue = nil }
                    }
            }
        }
        .animation(DSMotion.sheetCurve, value: item.wrappedValue)
    }
}
