/*
 * Purpose: Drills hub — canvas 5b `dIsHub` (phone, .compact CANON for Task 2):
 *          the ONE glass gauntlet hero (six-types grid, DAY N, begin/see-result,
 *          RESETS footer + submitted percentile), the 16-bar 4-week trend (I2
 *          deviation: rendered from raw daily score, not a daily-percentile
 *          series — see DrillsViewModel), and the C-14 group board (Task 3
 *          adds the WHARTON/GLOBAL/SCHOOLS scope switcher over `boardsSection`).
 * Inputs: DrillsViewModel (injectable; DEBUG fixture init for shots).
 * Outputs: none (navigation via AppRouter.shared).
 * Run: mounted by RootShell for DSTab.drills.
 */

import SwiftUI

struct DrillsView: View {
    @Environment(\.dsPalette) private var palette
    @State private var viewModel: DrillsViewModel

    // Injectable VM (default = live). The DEBUG -F7Drills hatch injects a
    // fixture-backed VM so simctl can capture a populated screen.
    @MainActor
    init(viewModel: DrillsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? DrillsViewModel())
    }

    var body: some View {
        ZStack {
            DSBackground()
            if viewModel.gauntlet == nil {
                Text("Loading today's gauntlet…").dsText(.meta).foregroundStyle(palette.muted)
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
                heroSection
                trendSection
                boardsSection
                Color.clear.frame(height: 120)   // room behind the tab bar
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .dsHeaderFade()
    }

    private var header: some View {
        Text("Drills").dsText(.h1Tab).foregroundStyle(palette.ink)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load() } } label: {
                Text("Retry").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 1. Gauntlet hero — the ONLY glass hero on this screen (canvas 5b 916-931)

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S GAUNTLET — SAME SIX FOR EVERYONE").dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                Text("DAY \(viewModel.streakDay)").dsText(.kicker).tabularNumbers().foregroundStyle(palette.green)
            }
            Text("Six types, five minutes.").dsText(.cardTitle).foregroundStyle(palette.ink)
                .padding(.bottom, 2)
            sixTypesGrid
                .padding(.bottom, 6)
            beginButton
            HStack(alignment: .firstTextBaseline) {
                Text("RESETS 06:00 · STREAK SAFE UNTIL 23:59").dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                if let label = viewModel.hubPercentileLabel {
                    Text(label).dsText(.kicker).tabularNumbers().foregroundStyle(palette.green)
                }
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
        .glassPanel(cornerRadius: 30)
    }

    /// 2-col, hairline underline on the first two rows only (4 labels) —
    /// fixed design-identity copy, NOT bound to live slot drillType (plan
    /// deviation #3).
    private var sixTypesGrid: some View {
        let labels = ["Mental math", "Market sizing", "Structures", "Chart reads", "Synthesis", "Estimates"]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 5) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.archivo(11.5, weight: 600))
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        if index < 4 {
                            Rectangle().fill(palette.hairline).frame(height: 1)
                        }
                    }
            }
        }
    }

    private var beginButton: some View {
        Button {
            AppRouter.shared.go(to: .gauntletRun)
        } label: {
            Text(viewModel.beginLabel)
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
    }

    // MARK: - 2. TREND — flat, hairline-top (canvas 5b 933-947)

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TREND — DAILY PERCENTILE, 4 WEEKS").dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                Text("MOSTLY UP").dsText(.kicker).foregroundStyle(palette.muted)
            }
            trendBarsRow
            weekLabelsRow
        }
        .padding(.top, 13)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    /// Square content only (reject-list: no rounded content corners).
    private var trendBarsRow: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(viewModel.trendBars) { bar in
                Rectangle()
                    .fill(bar.isGreen ? palette.green : palette.ink.opacity(bar.opacity))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(56 * bar.height, 4))
            }
        }
        .frame(height: 56)
    }

    private var weekLabelsRow: some View {
        HStack {
            ForEach(Array(viewModel.weekLabels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.archivo(8.5, weight: 600))
                    .tracking(0.12 * 8.5)
                    .tabularNumbers()
                    .foregroundStyle(index == viewModel.weekLabels.count - 1 ? palette.muted : palette.faint)
                if index < viewModel.weekLabels.count - 1 { Spacer() }
            }
        }
    }

    // MARK: - 3. BOARD — flat, hairline-top (canvas 5b 949-983). Task 2 ships
    // the complete C-14 group scope; `boardsSection` is the structural seam
    // Task 3 replaces with the 4-scope switcher.

    private var boardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.boardHead).dsText(.kicker).foregroundStyle(palette.muted)
                Spacer()
                if let note = viewModel.boardNote {
                    Text(note).font(.archivo(9, weight: 600)).tracking(0.1 * 9)
                        .tabularNumbers().foregroundStyle(palette.muted)
                }
            }
            boardRows
            Text("Drill percentiles are public. Session grades stay private.")
                .dsText(.serif(12, italic: true)).foregroundStyle(palette.muted)
                .padding(.top, 10)
        }
        .padding(.top, 13)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    private var boardRows: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.board?.entries ?? []) { entry in
                if entry.rank == 6 {
                    topFiveDivider
                }
                boardRow(entry)
            }
        }
        .padding(.top, 8)
    }

    private var topFiveDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            Text("TOP FIVE ADVANCE").font(.archivo(8, weight: 600)).tracking(0.15 * 8)
                .foregroundStyle(palette.muted)
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
        .padding(.vertical, 5)
    }

    private func boardRow(_ entry: BoardEntry) -> some View {
        let isYou = viewModel.isYourRow(entry)
        return HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.archivo(12.5, weight: 800)).tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(width: 28, alignment: .leading)
            Text(entry.displayName)
                .font(.archivo(13, weight: isYou ? 700 : 400))
                .foregroundStyle(palette.ink)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.points)")
                .font(.archivo(13, weight: 700)).tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 11)
        .background(isYou ? palette.surface.opacity(0.55) : Color.clear)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }
}

#if DEBUG
/// Screenshot/preview-only fixture (the July-16 phone persona, submitted):
/// streak 12, gauntlet result dailyPercentile 66, C-14 rank 6 / 8 behind №5,
/// 16 days of upward-trending daily scores, the same C-14 board HomeView's
/// fixture uses (Amara rank 6).
enum PreviewDrillsFixture {
    static let gauntlet = Gauntlet(
        date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
        slots: (1...6).map { GauntletSlot(slot: $0, drillType: "mental_math", key: "k\($0)", prompt: "p\($0)", numbers: [], choices: nil) },
        streak: 12, submitted: true,
        result: GauntletResult(
            score: 5, slotsCorrect: 5, slots: 6, pointsAwarded: 40,
            dailyPercentile: 66,
            group: GauntletGroup(groupId: 14, name: "C-14", rank: 6, points: 331, pointsBehindNext: 8),
            schoolPercentile: 71, vsPeersDelta: 3, weakSection: WeakSection(drillType: "market_sizing", label: "market sizing"),
            streak: 12, setKey: "set-2026-07-16"))

    static let trends = GauntletTrends(
        daily: Self.trailingDays(16), byType: [], weakest: "market_sizing")

    private static func trailingDays(_ count: Int) -> [TrendPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 16; comps.hour = 12
        let end = Calendar.current.date(from: comps)!
        let scores: [Double] = [2, 3, 3, 4, 3, 4, 5, 4, 5, 4, 5, 6, 5, 6, 5, 5]
        return (0..<count).map { i in
            let date = Calendar.current.date(byAdding: .day, value: -(count - 1 - i), to: end)!
            return TrendPoint(date: formatter.string(from: date), score: scores[i % scores.count])
        }
    }

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
}

#Preview {
    DrillsView(viewModel: .init(
        fixtureGauntlet: PreviewDrillsFixture.gauntlet,
        fixtureTrends: PreviewDrillsFixture.trends,
        fixtureBoard: PreviewDrillsFixture.board))
}
#endif
