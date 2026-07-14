/*
 * Purpose: Rubric-scoring subview — the 5 dimensions, each with a 0–maxPoints
 *          segmented control + per-item note, an overall notes editor, and a
 *          live grade-preview readout, all bound to RubricViewModel.
 * Inputs: RubricViewModel (loaded by the host InterviewerLiveView).
 * Outputs: none (edits flow through the view model's score/setNote/
 *          setOverallNotes, which schedule the debounced autosave).
 * Run: embedded in InterviewerLiveView.
 */

import SwiftUI

struct RubricView: View {
    var viewModel: RubricViewModel

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
        HStack {
            Text("Grade Preview")
                .font(.headline)
            Spacer()
            Text(String(format: "%.1f", viewModel.gradePreview))
                .font(.title2.bold())
                .foregroundStyle(Color("BrandAccent"))
        }
    }

    // Inline, dismissible — an autosave failure shouldn't blow away the
    // scoring UI the way a full-page ContentUnavailableView would.
    @ViewBuilder
    private var autosaveErrorBanner: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.footnote)
                Spacer()
                Button {
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func dimensionRow(for item: RubricTemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.label)
                .font(.subheadline.weight(.semibold))

            Picker(
                item.label,
                selection: Binding(
                    get: { viewModel.items[item.id]?.points ?? 0 },
                    set: { viewModel.score(itemId: item.id, points: $0) }
                )
            ) {
                ForEach(0...item.maxPoints, id: \.self) { point in
                    Text("\(point)").tag(point)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Color("BrandAccent"))

            TextField(
                "Note",
                text: Binding(
                    get: { viewModel.items[item.id]?.note ?? "" },
                    set: { viewModel.setNote(itemId: item.id, note: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.footnote)
        }
    }

    private var overallNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overall Notes")
                .font(.headline)
            TextEditor(
                text: Binding(
                    get: { viewModel.notesMd },
                    set: { viewModel.setOverallNotes($0) }
                )
            )
            .frame(minHeight: 100)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }
    }
}

#Preview {
    RubricView(
        viewModel: RubricViewModel(sessionId: 1, service: APIClient.shared)
    )
    .padding()
}
