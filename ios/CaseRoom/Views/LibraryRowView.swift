/*
 * Purpose: A single Library casebook row (canvas 5a/2c) — 40|1fr|auto grid:
 *          ordinal, kicker/title/meta column, trailing FOR YOU/SCHEDULED tag.
 *          Retired (done) rows grey out per Design Decisions §0.4. Also hosts
 *          LibraryDividerRow, the "DONE — YOURS TO INTERVIEW WITH" separator.
 * Inputs: LibraryCase, isSelected (tablet, Task 5), onTap.
 * Outputs: none.
 * Run: `LibraryRowView(row: case) { AppRouter.shared.go(to: .caseDetail(id)) }`
 *      in a phone list (Task 3) or with isSelected/select-on-tap (Task 5).
 *
 * Grey-token note (Task 3, F0 no-hex-elsewhere rule): the canvas retired
 * palette (#D3DAE3 ordinal, #B9C2CF kicker/meta) has no exact F0 token — both
 * are approximated as `palette.faint` at reduced opacity (lighter than faint's
 * own #A9B4C4, matching the canvas's direction) rather than adding new hex.
 * Retired title (#A9B4C4) and the row hairline (#DDE3EB) DO have exact token
 * matches (`palette.faint`, `palette.hairlineSoft`) and use them directly.
 */

import SwiftUI

struct LibraryRowView: View {
    let row: LibraryCase
    var isSelected: Bool = false
    let onTap: () -> Void

    @Environment(\.dsPalette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.ordinal)
                    .font(.archivo(24, weight: 400))
                    .tabularNumbers()
                    .foregroundStyle(ordinalColor)
                    .frame(width: 40, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.kicker)
                        .font(.archivo(8.5, weight: 600))
                        .tracking(8.5 * 0.13)
                        .foregroundStyle(kickerColor)
                    Text(row.title)
                        .font(.archivo(14.5, weight: 700))
                        .tracking(-0.145)
                        .lineLimit(2)
                        .foregroundStyle(titleColor)
                    Text(row.meta)
                        .font(.archivo(11, weight: 400))
                        .foregroundStyle(metaColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let tag = tagText {
                    Text(tag)
                        .font(.archivo(9, weight: 600))
                        .tracking(9 * 0.11)
                        .foregroundStyle(tagColor)
                        .fixedSize()
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .background {
            // Square content corners (F0 §5 rule: capsule only for glass
            // chips/pills/buttons) — Rectangle, not the capsule glassChip().
            if isSelected { GlassSurface(shape: Rectangle(), kind: .chip) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairlineSoft).frame(height: 1)
        }
    }

    private var ordinalColor: Color { row.done ? palette.faint.opacity(0.55) : palette.faint }
    private var kickerColor: Color { row.done ? palette.faint.opacity(0.85) : palette.muted }
    private var titleColor: Color { row.done ? palette.faint : palette.ink }
    private var metaColor: Color { row.done ? palette.faint.opacity(0.85) : palette.muted }

    private var tagText: String? {
        if row.recommended { return "FOR YOU" }
        if row.scheduledNote != nil { return "SCHEDULED" }
        return nil
    }
    private var tagColor: Color { row.recommended ? palette.green : palette.faint }
}

/// The "DONE — YOURS TO INTERVIEW WITH" separator between open and retired rows.
struct LibraryDividerRow: View {
    let label: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.archivo(8, weight: 600))
                .tracking(8 * 0.15)
                .foregroundStyle(palette.faint)
                .fixedSize()
            Rectangle().fill(palette.hairlineSoft).frame(height: 1)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}
