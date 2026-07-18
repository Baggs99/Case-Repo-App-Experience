/*
 * Purpose: The shared score-cell strip — cells 1…N, filled green up to `value`.
 *          One component, three sizes (§6 pinned contract): .large (recap 1–5
 *          pills), .medium (24pt rubric/debrief squares), .small (16pt live
 *          mini-cells). Tabular numerals always.
 * Inputs: count, value, size, interactive, onSelect, \.dsPalette.
 * Outputs: ScoreCells (View), ScoreCellSize.
 * Run: `ScoreCells(count: 5, value: rating, size: .large, interactive: true) { rating = $0 }`.
 */

import SwiftUI

enum ScoreCellSize {
    case large, medium, small

    var height: CGFloat { switch self { case .large: 46; case .medium: 24; case .small: 16 } }
    var corner: CGFloat { switch self { case .large: 40; case .medium: 6; case .small: 4 } }
    var gap: CGFloat { switch self { case .large: 6; case .medium: 5; case .small: 3 } }
    var font: Font {
        switch self {
        case .large:  return .archivo(14, weight: 600)
        case .medium: return .archivo(11, weight: 600)
        case .small:  return .archivo(8.5, weight: 600)
        }
    }
}

struct ScoreCells: View {
    let count: Int
    let value: Int
    var size: ScoreCellSize = .medium
    var interactive: Bool = false
    /// Whether each cell prints its digit. Default `true` preserves every F5
    /// call site (debrief/recap/left-pane) byte-for-byte; the F6 tablet rail
    /// passes `false` for the canvas's blank 16px heat-strip (Tablet 1a l.805).
    var showsNumbers: Bool = true
    var onSelect: ((Int) -> Void)? = nil
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: size.gap) {
            ForEach(1...max(count, 1), id: \.self) { n in cell(n) }
        }
    }

    @ViewBuilder private func cell(_ n: Int) -> some View {
        let filled = n <= value
        let shape = RoundedRectangle(cornerRadius: size.corner, style: .continuous)
        // Blank when showsNumbers is false (canvas rail heat-strip); the empty
        // string keeps the frame/tap target identical to the numbered cell.
        let label = Text(showsNumbers ? "\(n)" : "")
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(filled ? palette.onInk : palette.muted)
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .background {
                if filled {
                    shape.fill(palette.green)
                } else {
                    Color.clear.glassChip().clipShape(shape)
                }
            }
            .overlay(shape.strokeBorder(filled ? Color.clear : palette.hairline, lineWidth: 1))

        if interactive {
            Button { onSelect?(n) } label: { label }
                .buttonStyle(DSPressStyle())
        } else {
            label
        }
    }
}
