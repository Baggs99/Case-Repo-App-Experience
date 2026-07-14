/*
 * Purpose: Debrief screen — interviewer reviews the rubric's grade preview
 *          with an optional override and finalizes; candidate sees a
 *          "waiting for feedback" state until finalized, then the released
 *          grade.
 * Inputs: SessionViewModel (drives finalize + exposes finalized/
 *         releasedGrade); RubricViewModel (interviewer only — supplies the
 *         grade preview, shared with InterviewerLiveView by SessionView).
 * Outputs: none directly — Finalize routes through
 *          SessionViewModel.finalize(grade:); SessionView dismisses on success.
 * Run: shown by SessionView while state is "debrief".
 */

import SwiftUI

struct DebriefView: View {
    var sessionViewModel: SessionViewModel
    var rubricViewModel: RubricViewModel?

    @State private var overrideText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sessionViewModel.role == "interviewer" {
                    interviewerContent
                } else {
                    candidateContent
                }
            }
            .padding()
        }
        .navigationTitle("Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if sessionViewModel.role == "interviewer", let rubricViewModel {
                await rubricViewModel.load()
            }
        }
    }

    // MARK: - Interviewer

    @ViewBuilder
    private var interviewerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grade Preview")
                .font(.headline)
            Text(formatted(rubricViewModel?.gradePreview ?? 0))
                .font(.system(.largeTitle, design: .rounded))
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Override Grade (optional)")
                .font(.headline)
            TextField("Leave blank to use the preview", text: $overrideText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
        Button("Finalize") {
            Task { await sessionViewModel.finalize(grade: Double(overrideText)) }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("BrandAccent"))
        .disabled(sessionViewModel.finalized)
    }

    // MARK: - Candidate

    @ViewBuilder
    private var candidateContent: some View {
        if sessionViewModel.finalized {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grade")
                    .font(.headline)
                Text(sessionViewModel.releasedGrade.map(formatted) ?? "Pending")
                    .font(.system(.largeTitle, design: .rounded))
            }
        } else {
            ContentUnavailableView("Waiting for feedback", systemImage: "hourglass")
        }
    }

    private func formatted(_ grade: Double) -> String {
        String(format: "%.1f", grade)
    }
}

#Preview {
    NavigationStack {
        DebriefView(
            sessionViewModel: SessionViewModel(
                sessionId: 1, service: APIClient.shared, signaling: SignalingClient()
            )
        )
    }
}
