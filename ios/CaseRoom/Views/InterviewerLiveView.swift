/*
 * Purpose: Interviewer's live screen — a client-side stopwatch (start/pause/
 *          reset, no server timer), an exhibit strip with per-exhibit Release
 *          controls, the rubric scoring subview, and a Move to Debrief action.
 * Inputs: sessionId; SessionService (default APIClient.shared) — or a
 *         pre-built RubricViewModel, shared with DebriefView by SessionView.
 * Outputs: none directly — actions flow through RubricViewModel (autosave,
 *          reveal, transition to "debrief").
 * Run: pushed for the interviewer once a session's state is "live".
 */

import SwiftUI

struct InterviewerLiveView: View {
    @State private var viewModel: RubricViewModel

    @State private var timerRunning = false
    @State private var timerStart: Date?
    @State private var accumulated: TimeInterval = 0

    init(sessionId: Int, service: SessionService = APIClient.shared) {
        _viewModel = State(initialValue: RubricViewModel(sessionId: sessionId, service: service))
    }

    // Accepts an already-constructed RubricViewModel so SessionView can share
    // the same instance with DebriefView's grade preview.
    init(viewModel: RubricViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                timerSection
                exhibitStrip
                RubricView(viewModel: viewModel)
                moveToDebriefButton
            }
            .padding()
        }
        .navigationTitle("Interviewer — Live")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Timer (purely local — no server timer exists)

    private var timerSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let displayed = accumulated + (timerRunning ? context.date.timeIntervalSince(timerStart ?? context.date) : 0)
            HStack {
                Text(formatted(displayed))
                    .font(.system(.title2, design: .monospaced))
                Spacer()
                Button(timerRunning ? "Pause" : "Start") {
                    toggleTimer(now: context.date, displayed: displayed)
                }
                .buttonStyle(.bordered)
                .tint(Color("BrandAccent"))
                Button("Reset") {
                    resetTimer()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func toggleTimer(now: Date, displayed: TimeInterval) {
        if timerRunning {
            accumulated = displayed
            timerStart = nil
            timerRunning = false
        } else {
            timerStart = now
            timerRunning = true
        }
    }

    private func resetTimer() {
        accumulated = 0
        timerStart = timerRunning ? Date() : nil
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Exhibit strip

    @ViewBuilder
    private var exhibitStrip: some View {
        if !viewModel.exhibits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exhibits")
                    .font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.exhibits, id: \.exhibitId) { exhibit in
                            VStack(spacing: 6) {
                                Text("#\(exhibit.idx + 1)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Release") {
                                    Task { await viewModel.reveal(exhibitId: exhibit.exhibitId) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color("BrandAccent"))
                            }
                            .padding(8)
                            .background(.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Move to debrief

    private var moveToDebriefButton: some View {
        Button("Move to Debrief") {
            Task { await viewModel.moveToDebrief() }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("BrandAccent"))
    }
}

#Preview {
    NavigationStack {
        InterviewerLiveView(sessionId: 1)
    }
}
