/*
 * Purpose: The floating glass CLOSE-OUT sheet (F5 Task 7, canvas 6b close-out) —
 *          the recap GATE. It floats over the T6 recap report scroll: a LOCKED
 *          "Read to the end — N% of the way there" line that unlocks at
 *          scrollBottom − 16, then the REQUIRED 1–5 "RATE THIS CASE" strip (shared
 *          ScoreCells) + optional thumbs, then "Close the recap" → recapClose →
 *          "Gate cleared." LIGHT palette (the recap cover is daylight).
 * Inputs: a RecapCloseOutViewModel, the unlocked flag + read progress (computed
 *         from the report's scroll metrics), the interviewer name (thumbs prompt),
 *         an onCleared dismissal, \.dsPalette.
 * Outputs: RecapCloseOutSheet (View), RecapScrollKey/RecapScrollSample/RecapScrollMetrics.
 * Run: mounted by RecapReportView in its `.overlay(alignment: .bottom)` T7 seam.
 */

import SwiftUI

// MARK: - Scroll observation seam (report → sheet)

/// Scroll metrics sampled from the recap report's ScrollView. `offset` is how far
/// the report has scrolled DOWN (>= 0); contentHeight/viewportHeight bound the
/// scrollable distance so the sheet can unlock at bottom − 16.
struct RecapScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

/// One sample of the report content's live offset + height, carried up via a
/// PreferenceKey (a single probe → last value wins).
struct RecapScrollSample: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
}

struct RecapScrollKey: PreferenceKey {
    static let defaultValue = RecapScrollSample()
    static func reduce(value: inout RecapScrollSample, nextValue: () -> RecapScrollSample) {
        value = nextValue()
    }
}

// MARK: - The close-out sheet

struct RecapCloseOutSheet: View {
    let model: RecapCloseOutViewModel
    let unlocked: Bool
    let progress: Double
    let interviewerName: String?
    let onCleared: @MainActor () -> Void
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if unlocked {
                unlockedContent
                    .transition(.dsRise)
            } else {
                lockedContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .glassSheet(cornerRadius: 32)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(DSMotion.sheetCurve, value: unlocked)
    }

    // MARK: LOCKED — read-to-the-end line + live progress

    private var lockedContent: some View {
        HStack(spacing: 8) {
            RecapPulseDot()
            Text("Read to the end — \(RecapCloseOutPresentation.percentLabel(progress)) of the way there")
                .dsText(.serif(12.5, italic: true))
                .monospacedDigit()   // tabular N%
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: UNLOCKED — RATE THIS CASE (required) + thumbs + Close

    private var unlockedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("RATE THIS CASE — REQUIRED")
                    .font(.archivo(9.5, weight: 600))
                    .tracking(9.5 * 0.15)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("GRADES THE CASE, NOT YOU")
                    .font(.archivo(9, weight: 600))
                    .tracking(9 * 0.1)
                    .foregroundStyle(palette.faint)
            }
            .padding(.bottom, 10)

            // SHARED ScoreCells (F0), .large 1–5 pills. Required: Close stays
            // disabled until a value is chosen.
            ScoreCells(count: 5, value: model.rating, size: .large, interactive: true) { n in
                model.pick(n)
            }
            .padding(.bottom, 13)

            // Optional feedback-quality thumbs — TEXT, not icons (secondary =
            // underline). Always sendable; the backend stores it only for a
            // non-guest interviewer.
            HStack(alignment: .firstTextBaseline) {
                Text(thumbPrompt)
                    .font(.archivo(12, weight: 400))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                HStack(spacing: 12) {
                    thumbButton("Worth it", value: true)
                    thumbButton("Thin", value: false)
                }
            }
            .padding(.bottom, 15)

            Button {
                Task { await model.close(onCleared: onCleared) }
            } label: {
                Text("Close the recap")
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(model.canClose ? palette.onInk : palette.faint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(model.canClose ? palette.ink : palette.ink.opacity(0.10)))
            }
            .buttonStyle(DSPressStyle())
            .disabled(!model.canClose)

            if let error = model.closeError {
                Text(error)
                    .dsText(.serif(12, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 8)
            }
        }
    }

    private var thumbPrompt: String {
        "\(RecapPresentation.attribution(interviewerName))'s feedback — worth their time?"
    }

    private func thumbButton(_ title: String, value: Bool) -> some View {
        Button {
            model.toggleThumb(value)
        } label: {
            Text(title)
                .font(.archivo(12, weight: 600))
                .foregroundStyle(model.thumbs == value ? palette.ink : palette.muted)
                .underline(true, pattern: .solid)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Locked pulse dot (faint, not green — this adds no green mark)

private struct RecapPulseDot: View {
    @Environment(\.dsPalette) private var palette
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(palette.faint)
            .frame(width: 5, height: 5)
            .opacity(dim ? 0.35 : 1)
            .onAppear { withAnimation(DSMotion.blink) { dim = true } }
    }
}
