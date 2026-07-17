/*
 * Purpose: The staircase mark — the only icon in the system. A Shape from the
 *          canvas path (M4 35 H15 V25 H26 V15 H37 V4 H45, viewBox 48×40) plus an
 *          ink→green gradient view with an optional trim-draw animation.
 * Inputs: \.dsPalette.
 * Outputs: StaircaseMark (Shape), StaircaseMarkView.
 * Run: `StaircaseMarkView(animated: true).frame(width: 24, height: 20)`.
 */

import SwiftUI

/// The staircase path in the native 48×40 viewBox, scaled to `rect`.
struct StaircaseMark: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 48, sy = rect.height / 40
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(4, 35))
        path.addLine(to: p(15, 35)); path.addLine(to: p(15, 25))
        path.addLine(to: p(26, 25)); path.addLine(to: p(26, 15))
        path.addLine(to: p(37, 15)); path.addLine(to: p(37, 4))
        path.addLine(to: p(45, 4))
        return path
    }
}

struct StaircaseMarkView: View {
    @Environment(\.dsPalette) private var palette
    var lineWidth: CGFloat = 5
    var animated: Bool = false
    /// Optional explicit endpoints (e.g. CASE circle: chalk→green on ink).
    var lowColor: Color? = nil
    var highColor: Color? = nil
    @State private var trim: CGFloat = 0

    var body: some View {
        StaircaseMark()
            .trim(from: 0, to: animated ? trim : 1)
            .stroke(
                LinearGradient(colors: [lowColor ?? palette.ink, highColor ?? palette.green],
                               startPoint: .bottom, endPoint: .top),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .miter))
            .aspectRatio(48.0 / 40.0, contentMode: .fit)
            .onAppear {
                guard animated else { return }
                trim = 0
                withAnimation(DSMotion.drawCurve) { trim = 1 }
            }
    }
}
