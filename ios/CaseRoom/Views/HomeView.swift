/*
 * Purpose: Home screen (canvas 3a, phone) — the date/greeting header, the ONE
 *          glass hero ("today's set" + streak strip + cohort footer), a light
 *          elevated "tonight" strip, and flat editorial DIAGNOSTIC + TIMELINE
 *          blocks. The whole timeline block and "Add a firm" push Timeline
 *          detail; the hero's "Begin" opens F1's legacy drill sheet (F7 seam).
 * Inputs: HomeViewModel (injectable; DEBUG fixture init for shots).
 * Outputs: none (navigation via AppRouter.shared; writes live in the VM).
 * Run: mounted by RootShell inside `NavigationStack(path: $router.homePath)`.
 */

import SwiftUI

struct HomeView: View {
    @Environment(\.dsPalette) private var palette
    @State private var viewModel: HomeViewModel

    // Injectable VM (default = live). The DEBUG -F2Home hatch injects a
    // fixture-backed VM so simctl can capture a populated screen.
    @MainActor
    init(viewModel: HomeViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? HomeViewModel())
    }

    var body: some View {
        ZStack {
            DSBackground()
            if viewModel.dashboard == nil {
                Text("Loading your day…").dsText(.meta).foregroundStyle(palette.muted)
            } else {
                content
            }
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                heroCard
                if !viewModel.tonightHidden {
                    tonightStrip
                }
                diagnosticBlock
                timelineBlock
                Color.clear.frame(height: 120)   // room behind the tab bar
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .dsHeaderFade()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load() } } label: {
                Text("Retry").dsText(.meta).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 1. Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.dateKicker).dsText(.kicker).foregroundStyle(palette.muted)
            Text(viewModel.greeting).dsText(.h1Tab).foregroundStyle(palette.ink)
        }
    }

    // MARK: - 2. The glass hero — the ONLY glass hero on this screen

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S SET — CLOSES 23:59").dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                Text("DAY \(viewModel.streakDay)").dsText(.kicker).foregroundStyle(palette.green)
            }
            Text(viewModel.heroTitle).dsText(.cardTitle).foregroundStyle(palette.ink)
            Text("A set now is the warm-up for tonight's case.")
                .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            streakStrip
            beginButton
            if !viewModel.cohortFooterHidden {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.cohortLine).dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer()
                    Text(viewModel.behindLine).dsText(.kicker).foregroundStyle(palette.muted)
                }
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
        .glassPanel(cornerRadius: 30)
    }

    private var streakStrip: some View {
        HStack(spacing: 3) {
            ForEach(Array(viewModel.streakCells.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 3)
                    .fill(streakCellColor(state))
                    .frame(height: 6)
            }
        }
        .padding(.bottom, 4)
    }

    private func streakCellColor(_ state: HomeViewModel.StreakCellState) -> Color {
        switch state {
        case .filled: return palette.green
        case .today: return viewModel.submitted ? palette.green : palette.ink.opacity(0.25)
        case .empty: return palette.ink.opacity(0.12)
        }
    }

    private var beginButton: some View {
        Button {
            AppRouter.shared.go(to: .drillRun)
        } label: {
            Text("Begin today's set")
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
    }

    // MARK: - 3. Tonight strip — light elevated card (deviation #1: canvas
    // 3a is a light near-white surface, not the dark session-takeover theme).

    private var tonightStrip: some View {
        Button {
            AppRouter.shared.selection = .caseTab
        } label: {
            HStack(spacing: 14) {
                BlinkDot(diameter: 7).environment(\.dsPalette, DSPalette.dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.tonightKicker).dsText(.kicker).foregroundStyle(DSPalette.dark.muted)
                    Text(viewModel.tonightLine).dsText(.rowTitleStrong).foregroundStyle(palette.ink)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 12)
                Text("Details").dsText(.meta).underline().foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 20).padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.surface)
                .shadow(color: Color.dsShadowInk.opacity(0.2), radius: 26, x: 0, y: 10)
        )
    }

    // MARK: - 4. Flat DIAGNOSTIC block

    private var diagnosticBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("DIAGNOSTIC — LAST 2 MONTHS").dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                Text(viewModel.casesLine).dsText(.kicker).foregroundStyle(palette.muted)
            }
            VStack(spacing: 9) {
                ForEach(viewModel.diagnosticBars) { bar in
                    diagnosticRow(bar)
                }
            }
            Rectangle().fill(palette.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next case for the gap:")
                    .dsText(.serif(13, italic: true)).foregroundStyle(palette.muted)
                Text(viewModel.recTitle)
                    .font(.archivo(15.5, weight: 700)).tracking(-0.015 * 15.5)
                    .foregroundStyle(palette.ink)
                Text(viewModel.recMeta).dsText(.meta).foregroundStyle(palette.muted)
            }
            HStack(spacing: 18) {
                Button {
                    AppRouter.shared.selection = .caseTab
                } label: {
                    Text("Get cased on this").dsText(.rowTitle).underline().foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await viewModel.swap() }
                } label: {
                    Text("Swap").dsText(.rowTitle).underline().foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    private func diagnosticRow(_ bar: HomeViewModel.DiagnosticBar) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(bar.label).dsText(.meta).foregroundStyle(palette.ink)
                if bar.isFocus {
                    Text("FOCUS").dsText(.timelineTag).foregroundStyle(palette.green)
                }
            }
            .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.ink.opacity(0.1))
                    Rectangle().fill(palette.ink).frame(width: geo.size.width * bar.width)
                }
            }
            .frame(height: 2)
            Text(bar.valueText).dsText(.meta).tabularNumbers().foregroundStyle(palette.muted)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - 5. Flat TIMELINE block — whole block + "Add a firm" both push .timelineDetail

    private var timelineBlock: some View {
        Button {
            AppRouter.shared.go(to: .timelineDetail)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TIMELINE — FIRM DEADLINES").dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer()
                    Text("Add a firm").dsText(.meta).underline().foregroundStyle(palette.muted)
                }
                SteppedTimeline(firms: viewModel.timelineFirms)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }
}

#if DEBUG
/// Screenshot/preview-only fixture in the live API model shapes (the July-16
/// phone persona, Decisions §3): streak 12, 6 gauntlet slots, cohort C-14
/// 6th of 10 / 8 behind, diagnostic Structure 8.2/Comm 7.4/Quant 6.8/Market
/// sizing 5.1 FOCUS with 14 cases, rec "EV charging — size the German
/// market", tonight M. Lindqvist 19:00 candidate, firms McKinsey/BCG/Bain.
enum PreviewHomeFixture {
    static let profile = ProfileDetail(
        id: 1, email: "amara.osei@wharton.upenn.edu", displayName: "Amara Osei",
        bio: "MBA '27", linkedinUrl: "https://linkedin.com/in/amara-osei", school: "Wharton", photoUrl: nil)

    static let gauntlet = Gauntlet(
        date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
        slots: (1...6).map { GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil) },
        streak: 12, submitted: false, result: nil)

    static let board = GroupBoard(
        scope: "group", group: GroupRef(id: 14, name: "C-14"),
        entries: [
            BoardEntry(userId: 10, displayName: "R. Vance", photoKey: nil, points: 400, rank: 1, streak: 20),
            BoardEntry(userId: 11, displayName: "P. Nair", photoKey: nil, points: 380, rank: 2, streak: 18),
            BoardEntry(userId: 12, displayName: "K. Chen", photoKey: nil, points: 360, rank: 3, streak: 15),
            BoardEntry(userId: 13, displayName: "S. Park", photoKey: nil, points: 350, rank: 4, streak: 14),
            BoardEntry(userId: 14, displayName: "T. Becker", photoKey: nil, points: 339, rank: 5, streak: 13),
            BoardEntry(userId: 1, displayName: "Amara Osei", photoKey: nil, points: 331, rank: 6, streak: 12),
            BoardEntry(userId: 15, displayName: "J. Silva", photoKey: nil, points: 320, rank: 7, streak: 11),
            BoardEntry(userId: 16, displayName: "M. Lindqvist", photoKey: nil, points: 310, rank: 8, streak: 9),
            BoardEntry(userId: 17, displayName: "A. Kim", photoKey: nil, points: 300, rank: 9, streak: 7),
            BoardEntry(userId: 18, displayName: "D. Ortiz", photoKey: nil, points: 290, rank: 10, streak: 5),
        ])

    static let dashboard = DashboardStats(
        sessionsFinalized: 9, streakWeeks: 3,
        nextSession: SessionSummary(
            id: 42, role: "candidate", otherUser: "M. Lindqvist",
            caseTitle: "Low-cost carrier enters the Nordic market",
            scheduledAt: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()),
            state: nil, endedAt: nil, grade: nil),
        streakDays: 12, drillDoneToday: false,
        dimensionAverages: nil,
        recommendations: [
            Recommendation(caseId: 301, title: "EV charging — size the German market",
                            caseType: "Market sizing", difficulty: "D3", why: nil, rule: nil),
        ],
        diagnostic: DiagnosticStats(
            casesDone60D: 14,
            dimensions: [
                DimensionScore(dimension: "structure", avgScore: 8.2, samples: 14),
                DimensionScore(dimension: "communication", avgScore: 7.4, samples: 14),
                DimensionScore(dimension: "quant", avgScore: 6.8, samples: 14),
                DimensionScore(dimension: "market_sizing", avgScore: 5.1, samples: 14),
            ],
            strengths: [], weaknesses: [], focusDimension: "market_sizing",
            trend: DiagnosticTrend(recentAvg: nil, previousAvg: nil, delta: nil, direction: nil)),
        timeline: nil)

    // McKinsey/BCG/Bain (+ passed Roland Berger) — the same July-16 persona
    // TimelineDetailView's own fixture already carries (canvas 3a + 7b agree).
    static let timelineDetail = PreviewTimelineFixture.detail
}

#Preview {
    HomeView(viewModel: .init(
        fixtureDashboard: PreviewHomeFixture.dashboard, fixtureGauntlet: PreviewHomeFixture.gauntlet,
        fixtureBoard: PreviewHomeFixture.board, fixtureProfile: PreviewHomeFixture.profile,
        fixtureTimeline: PreviewHomeFixture.timelineDetail))
}
#endif
