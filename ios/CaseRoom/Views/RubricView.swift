/*
 * Purpose: Rubric-scoring subview — the dimensions, each with a shared ScoreCells
 *          1–N strip + per-item note, an overall notes editor, and a live
 *          running-average readout, all bound to RubricViewModel. Restyled onto
 *          the F0 token layer so it reads correctly under both the dark LIVE
 *          takeover and (via \.dsPalette) the light debrief.
 * Inputs: RubricViewModel (loaded by the host InterviewerLiveView).
 * Outputs: none (edits flow through the view model's score/setNote/
 *          setOverallNotes, which schedule the debounced autosave).
 * Run: embedded in InterviewerLiveView.
 */

import SwiftUI

struct RubricView: View {
    var viewModel: RubricViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            gradePreviewSection
            autosaveErrorBanner

            ForEach(viewModel.templateItems, id: \.id) { item in
                dimensionRow(for: item)
            }

            overallNotesSection
        }
    }

    private var gradePreviewSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("RUBRIC — LIVE")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.15)
                .foregroundStyle(palette.muted)
            Spacer()
            Text(String(format: "%.1f", viewModel.gradePreview))
                .font(.archivo(20, weight: 700))
                .tabularNumbers()
                .foregroundStyle(palette.green)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    // Inline, dismissible — an autosave failure shouldn't blow away the scoring
    // UI. Text-only (no icons per the reject-list).
    @ViewBuilder
    private var autosaveErrorBanner: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(alignment: .firstTextBaseline) {
                Text(errorMessage)
                    .dsText(.serif(13, italic: true))
                    .foregroundStyle(palette.muted)
                Spacer()
                Button("Dismiss") { viewModel.errorMessage = nil }
                    .font(.archivo(11.5, weight: 600))
                    .foregroundStyle(palette.muted)
                    .underline(true, pattern: .solid)
                    .buttonStyle(.plain)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1))
        }
    }

    private func dimensionRow(for item: RubricTemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label)
                .font(.archivo(12, weight: 600))
                .foregroundStyle(palette.ink)

            ScoreCells(
                count: item.maxPoints,
                value: viewModel.items[item.id]?.points ?? 0,
                size: .small,
                interactive: true
            ) { points in
                viewModel.score(itemId: item.id, points: points)
            }

            TextField(
                "Evidence",
                text: Binding(
                    get: { viewModel.items[item.id]?.note ?? "" },
                    set: { viewModel.setNote(itemId: item.id, note: $0) }
                )
            )
            .font(.serifVoice(12.5, italic: true))
            .foregroundStyle(palette.muted)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
        }
    }

    private var overallNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OVERALL NOTES")
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.15)
                .foregroundStyle(palette.muted)
            TextEditor(
                text: Binding(
                    get: { viewModel.notesMd },
                    set: { viewModel.setOverallNotes($0) }
                )
            )
            .font(.serifVoice(13))
            .foregroundStyle(palette.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 90)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1))
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        RubricView(viewModel: RubricViewModel(sessionId: 1, service: APIClient.shared))
            .padding()
    }
    .dsTheme(.dark)
}
#endif
