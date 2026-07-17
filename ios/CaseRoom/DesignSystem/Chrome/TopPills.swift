/*
 * Purpose: Floating top-pill chrome — the wordmark chip (mark + serif-italic "my"
 *          + Archivo-800 "Case"), the avatar pill (40px glass over a 28px ink
 *          circle), and the sub-page back pill (‹ Back + slate context label).
 * Inputs: initials / labels, \.dsPalette.
 * Outputs: WordmarkChip, AvatarPill, BackPill.
 * Run: `WordmarkChip()`, `AvatarPill(initials: "AO")`, `BackPill(label: "Community", context: "GROUP")`.
 */

import SwiftUI

struct WordmarkChip: View {
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            StaircaseMarkView().frame(width: 20, height: 17)
            (Text("my").font(.serifVoice(15, italic: true))
             + Text("Case").font(.archivo(15, weight: 800)).tracking(-0.3))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassChip()
    }
}

struct AvatarPill: View {
    let initials: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack {
            Circle().fill(palette.ink).frame(width: 28, height: 28)
            Text(initials)
                .font(.archivo(10.5, weight: 700))
                .foregroundStyle(palette.onInk)
        }
        .frame(width: 40, height: 40)
        .glassChip()
    }
}

struct BackPill: View {
    let label: String
    var context: String? = nil
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack {
            Text("‹ \(label)").dsText(.rowTitle).foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            if let context {
                Text(context).dsText(.kicker).foregroundStyle(palette.muted)
            }
        }
    }
}
