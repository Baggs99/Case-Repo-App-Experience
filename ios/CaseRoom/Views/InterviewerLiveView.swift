/*
 * Purpose: Interviewer's dark LIVE screen (canvas 4a interviewer) — the glass
 *          clock pill over the existing view-local stopwatch (Start/Pause/Reset),
 *          the striped candidate pane, an exhibit-release strip, the live rubric
 *          (RubricView, restyled onto dark tokens + shared ScoreCells), and Move
 *          to Debrief. All actions still flow through the unchanged
 *          RubricViewModel (autosave / reveal / debrief transition).
 * Inputs: a RubricViewModel (shared with DebriefView's grade preview by
 *         SessionView); the candidate (peer) name + whether to show the compact
 *         peer pane, supplied by SessionView.
 * Outputs: none directly.
 * Run: shown by SessionView while state == "live" for the interviewer.
 */

import SwiftUI

struct InterviewerLiveView: View {
    @State private var viewModel: RubricViewModel
    var peerName: String
    var showsInterviewerPane: Bool

    @State private var timerRunning = false
    @State private var timerStart: Date?
    @State private var accumulated: TimeInterval = 0
    @Environment(\.dsPalette) private var palette

    init(sessionId: Int, service: SessionService = APIClient.shared) {
        _viewModel = State(initialValue: RubricViewModel(sessionId: sessionId, service: service))
        self.peerName = "Your candidate"
        self.showsInterviewerPane = false
    }

    // Accepts an already-constructed RubricViewModel so SessionView can share
    // the same instance with DebriefView's grade preview.
    init(viewModel: RubricViewModel, peerName: String = "Your candidate", showsInterviewerPane: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.peerName = peerName
        self.showsInterviewerPane = showsInterviewerPane
    }

    var body: some View {
        ZStack {
            DSBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    exhibitStrip
                    RubricView(viewModel: viewModel)
                    moveToDebriefButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    // MARK: - Header (clock pill + candidate pane + stopwatch controls)

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let displayed = accumulated + (timerRunning ? context.date.timeIntervalSince(timerStart ?? context.date) : 0)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    LiveClockPill(text: SessionClock.mmss(displayed))
                    Spacer()
                    if showsInterviewerPane {
                        PeerVideoPane(name: peerName)
                    }
                }
                HStack(spacing: 20) {
                    underlineControl(timerRunning ? "Pause" : "Start") {
                        toggleTimer(now: Date(), displayed: displayed)
                    }
                    underlineControl("Reset") { resetTimer() }
                }
            }
        }
    }

    private func underlineControl(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.archivo(12.5, weight: 600))
                .foregroundStyle(palette.muted)
                .underline(true, pattern: .solid)
        }
        .buttonStyle(.plain)
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

    // MARK: - Exhibit release strip

    @ViewBuilder
    private var exhibitStrip: some View {
        if !viewModel.exhibits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("EXHIBITS")
                    .font(.archivo(9, weight: 600))
                    .tracking(9 * 0.14)
                    .foregroundStyle(palette.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.exhibits, id: \.exhibitId) { exhibit in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(LivePresentation.pillLabel(idx: exhibit.idx))
                                    .font(.archivo(11, weight: 600))
                                    .foregroundStyle(palette.ink)
                                Button {
                                    Task { await viewModel.reveal(exhibitId: exhibit.exhibitId) }
                                } label: {
                                    Text("Release")
                                        .font(.archivo(11.5, weight: 600))
                                        .foregroundStyle(palette.onInk)
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background(Capsule().fill(palette.ink))
                                }
                                .buttonStyle(DSPressStyle())
                            }
                            .padding(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(palette.hairline, lineWidth: 1)
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Move to debrief

    private var moveToDebriefButton: some View {
        Button {
            Task { await viewModel.moveToDebrief() }
        } label: {
            Text("Move to Debrief")
                .font(.archivo(14, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(palette.ink))
        }
        .buttonStyle(DSPressStyle())
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        InterviewerLiveView(viewModel: RubricViewModel(sessionId: 1, service: APIClient.shared),
                            peerName: "Amara Osei", showsInterviewerPane: true)
    }
    .dsTheme(.dark)
}
#endif
