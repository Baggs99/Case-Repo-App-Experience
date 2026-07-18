/*
 * Purpose: Shared presentation pieces for the dark LIVE takeover (canvas 4a/4b) —
 *          the glass clock pill + its pure MM:SS formatter, the compact striped
 *          peer-video placeholder, the CASE/EX new-dot derivation, and the
 *          revealed-exhibit content model (table + unit-cost bars) with its
 *          render views. All PRESENTATION ONLY: nothing here touches the
 *          transport/crypto/signaling seam — the exhibit content is decoded from
 *          the plaintext ExhibitsViewModel already publishes, falling back to the
 *          existing image path when the payload isn't structured content.
 * Inputs: \.dsPalette (dark under the takeover); decoded exhibit plaintext.
 * Outputs: SessionClock, LiveClockPill, PeerVideoPane, LivePresentation,
 *          ExhibitContent (+ ExhibitContentView).
 * Run: consumed by CandidateLiveView / InterviewerLiveView / SessionView.
 */

import SwiftUI

// MARK: - Clock formatter (pure — the one genuinely new testable bit)

enum SessionClock {
    /// Clamped MM:SS from an elapsed interval. Tabular by contract at the call
    /// site (LiveClockPill uses .tabularNumbers()).
    static func mmss(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Glass clock pill (canvas 4a/4b: dark glass, blink dot, tabular time)

/// The live clock display — a dark glass capsule with the green BlinkDot and the
/// tabular MM:SS. Pure display: callers own the timer source and pass the text
/// (re-skin of the existing live-view stopwatch, not a new clock model).
struct LiveClockPill: View {
    let text: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            BlinkDot()
            Text(text)
                .font(.archivo(15, weight: 800))
                .tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 15)
        .frame(height: 38)
        .glassChip()
    }
}

// MARK: - Compact peer-video placeholder (canvas 4a/4b striped pane)

/// The 96×62 striped peer pane shown in the live header (the interviewer's feed
/// for the candidate, the candidate's for the interviewer). Pure SwiftUI: it is
/// the placeholder that stands in until — on a real remote device — the WebRTC
/// surface (VideoCallView) mounts. Stripes are drawn, not an asset.
struct PeerVideoPane: View {
    let name: String
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .overlay(DiagonalStripes(color: palette.ink.opacity(0.05)))

            Text(name)
                .font(.archivo(8.5, weight: 600))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.page.opacity(0.6)))
                .padding(.leading, 7)
                .padding(.bottom, 5)
        }
        .frame(width: 96, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.ink.opacity(0.14), lineWidth: 1)
        )
    }
}

/// 135° chalk stripes (7px stroke every 14px) — the interviewer-pane texture.
struct DiagonalStripes: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 14
            let h = size.height
            var x: CGFloat = -h
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: h))
                line.addLine(to: CGPoint(x: x + h, y: 0))
                context.stroke(line, with: .color(color), lineWidth: 7)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CASE/EX new-dot derivation (pure — drives the pill dots + toast)

enum LivePresentation {
    /// Exhibit ids that should carry a new-dot: revealed but not yet opened.
    /// Drives the per-pill green dot (canvas e1New/e2New) purely from
    /// ExhibitsViewModel's already-published revealed state — no signaling.
    static func newDotIds(revealed: Set<Int>, seen: Set<Int>) -> Set<Int> {
        revealed.subtracting(seen)
    }

    /// "EX 01" / "EX 02" segmented-pill label for a zero-based exhibit index.
    static func pillLabel(idx: Int) -> String { String(format: "EX %02d", idx + 1) }

    /// "EXHIBIT 01" panel kicker for a zero-based exhibit index.
    static func panelLabel(idx: Int) -> String { String(format: "EXHIBIT %02d", idx + 1) }

    /// The reveal toast copy (canvas toast on release).
    static func revealToast(idx: Int) -> String { String(format: "Exhibit %02d released", idx + 1) }
}

// MARK: - Revealed exhibit content (table + unit-cost bars)

/// Structured exhibit content the candidate view renders natively (tokens +
/// tabular numerals, per the reject-list). Decoded from the plaintext bytes
/// ExhibitsViewModel reveals; production image exhibits simply fail this decode
/// and fall back to the existing UIImage path.
struct ExhibitContent: Decodable, Equatable {
    let title: String
    var releasedAt: String? = nil
    var table: Table? = nil
    var bars: Bars? = nil

    struct Table: Decodable, Equatable {
        let columns: [String]
        let rows: [Row]
        struct Row: Decodable, Equatable {
            let cells: [String]
            // Optional (not `= false`): synthesized Decodable ignores defaults on
            // non-optional keys, so a missing key must not throw.
            var total: Bool?
        }
    }

    struct Bars: Decodable, Equatable {
        let title: String
        let scaleMax: Double
        let items: [Bar]
        var footnote: String? = nil
        struct Bar: Decodable, Equatable {
            let label: String
            let value: Double
            var highlight: Bool?
        }
    }

    static func decode(from data: Data) -> ExhibitContent? {
        try? JSONDecoder().decode(ExhibitContent.self, from: data)
    }
}

/// Renders a revealed exhibit's glass panel: header (EXHIBIT 0N · RELEASED),
/// title, the volumes/fares table, then the unit-cost bars.
struct ExhibitContentView: View {
    let panelLabel: String
    let content: ExhibitContent
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(panelLabel)
                    .font(.archivo(9, weight: 600))
                    .tracking(9 * 0.14)
                    .foregroundStyle(palette.muted)
                Spacer()
                if let released = content.releasedAt {
                    Text("RELEASED \(released)")
                        .font(.archivo(9, weight: 600))
                        .tracking(9 * 0.1)
                        .tabularNumbers()
                        .foregroundStyle(palette.faint)
                }
            }
            .padding(.bottom, 12)

            Text(content.title)
                .font(.archivo(15, weight: 700))
                .foregroundStyle(palette.ink)
                .padding(.bottom, 14)

            if let table = content.table {
                ExhibitTableView(table: table)
            }

            if let bars = content.bars {
                if content.table != nil {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                        .padding(.vertical, 16)
                }
                Text(bars.title)
                    .font(.archivo(15, weight: 700))
                    .foregroundStyle(palette.ink)
                    .padding(.bottom, 16)
                UnitCostBars(bars: bars)
                if let footnote = bars.footnote {
                    Text(footnote)
                        .dsText(.serif(11.5, italic: true))
                        .foregroundStyle(palette.faint)
                        .padding(.top, 14)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 26)
    }
}

/// The volumes/fares table (canvas: COUNTRY | PAX / YR | AVG FARE, total bold).
private struct ExhibitTableView: View {
    let table: ExhibitContent.Table
    @Environment(\.dsPalette) private var palette

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            GridRow {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { idx, col in
                    Text(col)
                        .font(.archivo(9, weight: 600))
                        .tracking(9 * 0.12)
                        .foregroundStyle(palette.faint)
                        .frame(maxWidth: .infinity, alignment: idx == 0 ? .leading : .trailing)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { idx, cell in
                        let isTotal = row.total ?? false
                        Text(cell)
                            .font(.archivo(13.5, weight: isTotal ? 700 : (idx == 0 ? 600 : 400)))
                            .tabularNumbers()
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: idx == 0 ? .leading : .trailing)
                            .padding(.top, 9)
                            .overlay(alignment: .top) {
                                Rectangle().fill(palette.hairline).frame(height: 1)
                            }
                    }
                }
            }
        }
    }
}

/// Horizontal unit-cost bars (canvas: 84px label | track | 34px value); the
/// lowest-cost competitor is the single green (advantage), the rest muted.
private struct UnitCostBars: View {
    let bars: ExhibitContent.Bars
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(bars.items.enumerated()), id: \.offset) { _, bar in
                HStack(spacing: 10) {
                    Text(bar.label)
                        .font(.archivo(12, weight: 600))
                        .foregroundStyle(palette.ink)
                        .frame(width: 84, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(palette.ink.opacity(0.08))
                            Rectangle()
                                .fill((bar.highlight ?? false) ? palette.green : palette.muted)
                                .frame(width: geo.size.width * fraction(bar.value))
                        }
                    }
                    .frame(height: 14)

                    Text(valueText(bar.value))
                        .font(.archivo(12))
                        .tabularNumbers()
                        .foregroundStyle(palette.ink)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private func fraction(_ value: Double) -> CGFloat {
        guard bars.scaleMax > 0 else { return 0 }
        return CGFloat(min(max(value / bars.scaleMax, 0), 1))
    }

    private func valueText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
