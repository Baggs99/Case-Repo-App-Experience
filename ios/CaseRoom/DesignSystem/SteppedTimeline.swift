/*
 * Purpose: The literal stepped timeline — a non-scaling 2px stepped line
 *          (path M2 58 H96 V42 H192 V24 H276 V8 H318, viewBox 320×64) with a green
 *          TODAY dot at the origin and a 3-column firm-label grid beneath.
 * Inputs: firms (name/date/days/readiness/onPace), \.dsPalette.
 * Outputs: StepPath (Shape), SteppedTimeline (View), TimelineFirm.
 * Run: `SteppedTimeline(firms: PreviewFixtures.phone.timeline)`.
 */

import SwiftUI

struct TimelineFirm: Identifiable {
    let id = UUID()
    let name: String
    let date: String       // "Sep 12"
    let days: String       // "58 days"
    let readiness: String  // "ON PACE" / "PUSH QUANT" / "EARLY"
    let onPace: Bool       // green only when true (owner: only McKinsey's ON PACE)
}

/// The stepped line, scaled non-uniformly to fill its rect (preserveAspectRatio:none).
struct StepPath: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 320, sy = rect.height / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(2, 58))
        path.addLine(to: p(96, 58)); path.addLine(to: p(96, 42))
        path.addLine(to: p(192, 42)); path.addLine(to: p(192, 24))
        path.addLine(to: p(276, 24)); path.addLine(to: p(276, 8))
        path.addLine(to: p(318, 8))
        return path
    }
}

struct SteppedTimeline: View {
    let firms: [TimelineFirm]
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                StepPath()
                    .stroke(palette.ink, lineWidth: 2)   // 2px stays 2px (points, non-scaling)
                Circle()
                    .fill(palette.green)
                    .frame(width: 7, height: 7)
                    .position(x: 2, y: geo.size.height / 64 * 58)   // TODAY dot at origin (2,58)
            }
            .frame(height: 64)

            HStack(alignment: .top, spacing: 8) {
                ForEach(firms) { firm in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(firm.name) · \(firm.date)").dsText(.rowTitle).foregroundStyle(palette.ink)
                        Text(firm.days).dsText(.meta).foregroundStyle(palette.muted)
                        Text(firm.readiness).dsText(.kicker)
                            .foregroundStyle(firm.onPace ? palette.green : palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
