/*
 * Purpose: The onboarding progress chrome — the staircase mark drawing itself as
 *          the flow advances (trim to progressStep/5, the native equivalent of
 *          the canvas dashoffset `74 − 74·(step/5)`), beside a "STEP N OF 05"
 *          kicker. The mark is the ONLY icon; no SF Symbols/emoji here.
 * Inputs: progressStep (0…5 from OnboardingViewModel); \.dsPalette.
 * Outputs: OnboardingProgressMark (a View).
 * Run: OnboardingRootView places it above each step (Task 7).
 */

import SwiftUI

struct OnboardingProgressMark: View {
    @Environment(\.dsPalette) private var palette
    let progressStep: Int

    var body: some View {
        HStack(spacing: 10) {
            // The whole staircase sits ghosted (hairline) so the box always reads
            // as the mark; the ink→green stroke inks OVER it as steps advance — the
            // "mark drawing itself" progress pattern, legible even at step 1.
            ZStack {
                StaircaseMark()
                    .stroke(palette.hairline,
                            style: StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .miter))
                StaircaseMark()
                    .trim(from: 0, to: CGFloat(progressStep) / 5)
                    .stroke(
                        LinearGradient(colors: [palette.ink, palette.green],
                                       startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .miter))
                    .animation(DSMotion.drawCurve, value: progressStep)
            }
            .aspectRatio(48.0 / 40.0, contentMode: .fit)
            .frame(width: 30, height: 25)

            Text("STEP \(stepNumber) OF 05")
                .dsText(.kicker)
                .tabularNumbers()
                .foregroundStyle(palette.muted)
        }
    }

    // Zero-padded to match the "05" total (tabular digits keep both aligned).
    private var stepNumber: String { String(format: "%02d", progressStep) }
}

#if DEBUG
private struct OnboardingProgressMarkPreview: View {
    @State private var step = 1
    var body: some View {
        ZStack {
            DSBackground()
            VStack(spacing: 24) {
                ForEach(1...5, id: \.self) { OnboardingProgressMark(progressStep: $0) }
                Button("Advance") { step = step % 5 + 1 }
            }
        }
    }
}

#Preview { OnboardingProgressMarkPreview() }
#endif
