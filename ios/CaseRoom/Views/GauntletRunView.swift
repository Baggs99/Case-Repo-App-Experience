/*
 * Purpose: The gauntlet run experience (canvas 5b run + result frames) — a
 *          full-screen immersive cover driven by GauntletRunViewModel's phase
 *          machine. Run frame: a green progress bar over a hairline track, a
 *          kicker + real MM:SS clock row, the 34px question, and per-slot input
 *          (GauntletKeypad for numeric slots, a 2×2 glass choice grid for choice
 *          slots), with an underline Abandon footer. Result frame: the staircase
 *          mark drawing in, the big percentile + ordinal, the elapsed kicker, a
 *          hairline stat strip (points / correct / rank-in-group), a serif line,
 *          and the weak-section CTA that bridges to the legacy FM practice drill
 *          (`.drillRun`) plus a "Back to Drills" dismiss. Result elements
 *          rise-stagger per canvas.
 * Inputs: a GauntletRunViewModel (live, injected, or fixture-backed).
 * Outputs: none (submit/timer/recovery side effects live in the VM); navigation
 *          via AppRouter.shared + \.dismiss.
 * Run: RootShell `.fullScreenCover(item:)` builds and presents it.
 */

import SwiftUI

struct GauntletRunView: View {
    let viewModel: GauntletRunViewModel
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DSBackground()
            switch viewModel.phase {
            case .loading:
                statusText("Loading today's gauntlet…")
            case .running:
                runFrame
            case .submitting:
                statusText("Scoring your gauntlet…")
            case .result:
                resultFrame
            case .failed(let message):
                failedFrame(message)
            }
        }
        .task { await viewModel.start() }
    }

    private func statusText(_ text: String) -> some View {
        Text(text).dsText(.meta).foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Run frame (canvas 5b run)

    private var runFrame: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                progressBar
                    .padding(.bottom, 16)
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.kicker)
                        .font(.archivo(9.5, weight: 600)).tracking(0.15 * 9.5)
                        .foregroundStyle(palette.muted)
                    Spacer()
                    Text(viewModel.timerLabel)
                        .font(.archivo(22, weight: 800)).tabularNumbers()
                        .foregroundStyle(palette.ink)
                }
                .padding(.bottom, 36)

                Text(viewModel.currentSlot?.prompt ?? "")
                    .font(.archivo(34, weight: 800)).tracking(-0.03 * 34).lineSpacing(5)
                    .tabularNumbers()
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 32)

                if viewModel.isNumericSlot {
                    GauntletKeypad(
                        input: $viewModel.numericInput,
                        isNegative: $viewModel.isNegative,
                        canAdvance: viewModel.canAdvance,
                        onAdvance: { Task { await viewModel.advance() } })
                } else {
                    choiceGrid(viewModel.currentSlot?.choices ?? [])
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer(minLength: 24)

            Button { viewModel.stop(); dismiss() } label: {
                Text("Abandon run — streak survives, score doesn't")
                    .dsText(.actionLabel).underline().foregroundStyle(palette.muted)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.hairline)
                Rectangle().fill(palette.green).frame(width: geo.size.width * viewModel.progress)
            }
        }
        .frame(height: 2)
        .animation(DSMotion.riseCurve, value: viewModel.progress)
    }

    private func choiceGrid(_ choices: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, label in
                Button { Task { await viewModel.selectChoice(index) } } label: {
                    Text(label)
                        .font(.archivo(17, weight: 600)).tabularNumbers()
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .glassKey(cornerRadius: 20)
                }
                .buttonStyle(DSPressStyle())
            }
        }
    }

    // MARK: - Result frame (canvas 5b result)

    private var resultFrame: some View {
        ResultContent(viewModel: viewModel, dismiss: { dismiss() })
    }

    private func failedFrame(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Back to Drills").dsText(.actionLabel).underline().foregroundStyle(palette.ink).padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// The result frame is a dedicated view so its one-shot rise-stagger `appeared`
// state has a stable home (the canvas .3/.4/.5/.62/.74s delays).
private struct ResultContent: View {
    let viewModel: GauntletRunViewModel
    let dismiss: () -> Void
    @Environment(\.dsPalette) private var palette
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            StaircaseMarkView(animated: true)
                .frame(width: 96, height: 80)
                .padding(.bottom, 16)

            percentile
                .rise(appeared, delay: 0.30)
                .padding(.bottom, 8)

            Text(viewModel.resultKicker)
                .font(.archivo(9.5, weight: 600)).tracking(0.16 * 9.5)
                .foregroundStyle(palette.faint)
                .multilineTextAlignment(.center)
                .rise(appeared, delay: 0.40)
                .padding(.bottom, 18)

            statStrip
                .rise(appeared, delay: 0.50)
                .padding(.bottom, 18)

            Text(viewModel.resultSerifLine)
                .dsText(.serif(15, italic: true))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .rise(appeared, delay: 0.62)
                .padding(.bottom, 26)

            ctaButtons
                .rise(appeared, delay: 0.74)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    private var percentile: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(viewModel.resultPercentileNumber)
                .font(.archivo(72, weight: 800)).tracking(-0.04 * 72).tabularNumbers()
            Text(viewModel.resultPercentileSuffix)
                .font(.archivo(28, weight: 800)).tabularNumbers()
                .padding(.top, 6)
        }
        .foregroundStyle(palette.ink)
    }

    private var statStrip: some View {
        HStack(spacing: 14) {
            Text(viewModel.resultPointsLabel)
                .font(.archivo(11, weight: 600)).tracking(0.1 * 11).tabularNumbers()
                .foregroundStyle(palette.green)
            Text(viewModel.resultCorrectLabel)
                .font(.archivo(11, weight: 600)).tracking(0.1 * 11).tabularNumbers()
                .foregroundStyle(palette.muted)
            if let groupLabel = viewModel.resultGroupLabel {
                Text(groupLabel)
                    .font(.archivo(11, weight: 600)).tracking(0.1 * 11).tabularNumbers()
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .bottom)
    }

    private var ctaButtons: some View {
        VStack(spacing: 10) {
            Button {
                // The FM practice bridge: dismiss the server-gauntlet cover, then
                // open the legacy on-device DrillView (.drillRun) unchanged.
                dismiss()
                AppRouter.shared.go(to: .drillRun)
            } label: {
                Text(viewModel.weakCtaLabel)
                    .dsText(.rowTitle).foregroundStyle(palette.onInk)
                    .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(DSPressStyle())
            .background(Capsule().fill(palette.ink))

            Button { dismiss() } label: {
                Text("Back to Drills").dsText(.actionLabel).underline().foregroundStyle(palette.ink).padding(6)
            }
            .buttonStyle(.plain)
        }
    }
}

// The canvas result-element rise: 8px up + fade, staggered by `delay`.
private extension View {
    func rise(_ appeared: Bool, delay: Double) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(DSMotion.riseCurve.delay(delay), value: appeared)
    }
}

#if DEBUG
/// Screenshot-only fixtures for the `-F7Run numeric|choice` + `-F7Result`
/// hatches. A constant clock keeps the run timer at 00:00 so the shots are
/// deterministic; the result hatch injects a 04:12 elapsed for the full kicker.
enum PreviewGauntletRunFixture {
    private static let fixedNow = Date(timeIntervalSince1970: 1_752_600_000)

    private static let numericSlots: [GauntletSlot] = [
        GauntletSlot(slot: 1, drillType: "mental_math", key: "k1",
                     prompt: "A unit's revenue rises from 4.2 to 5.7. What is the percent change, to the nearest whole percent?",
                     numbers: [], choices: nil),
        GauntletSlot(slot: 2, drillType: "mental_math", key: "k2", prompt: "17 × 24 = ?", numbers: [], choices: nil),
    ]

    private static let choiceSlots: [GauntletSlot] = [
        GauntletSlot(slot: 1, drillType: "market_sizing", key: "k1",
                     prompt: "Best first cut to size the US coffee-shop market?",
                     numbers: [],
                     choices: ["Population × spend", "Stores × revenue", "Households × trips", "GDP × share"]),
        GauntletSlot(slot: 2, drillType: "mental_math", key: "k2", prompt: "17 × 24 = ?", numbers: [], choices: nil),
    ]

    private static func gauntlet(_ slots: [GauntletSlot]) -> Gauntlet {
        Gauntlet(date: "2026-07-16", setKey: "set-2026-07-16", provisional: false,
                 slots: slots, streak: 12, submitted: false, result: nil)
    }

    static let result = GauntletResult(
        score: 5, slotsCorrect: 5, slots: 6, pointsAwarded: 40,
        dailyPercentile: 66,
        group: GauntletGroup(groupId: 14, name: "C-14", rank: 3, points: 331, pointsBehindNext: 8),
        schoolPercentile: 71, vsPeersDelta: 3,
        weakSection: WeakSection(drillType: "market_sizing", label: "market sizing"),
        streak: 12, setKey: "set-2026-07-16")

    @MainActor
    static func runVM(mode: String?) -> GauntletRunViewModel {
        // start() resets per-slot input on entry, so each slot opens on a fresh
        // keypad — the shot shows the honest arrive-at-slot state (Next disabled
        // until a value is entered).
        let slots = mode == "choice" ? choiceSlots : numericSlots
        return GauntletRunViewModel(preloaded: gauntlet(slots), now: { fixedNow }, autoTick: false)
    }

    @MainActor
    static let resultVM = GauntletRunViewModel(
        preloadedResult: result, preloadedElapsedSeconds: 252, now: { fixedNow }, autoTick: false)
}

#Preview("Run — numeric") { GauntletRunView(viewModel: PreviewGauntletRunFixture.runVM(mode: "numeric")) }
#Preview("Result") { GauntletRunView(viewModel: PreviewGauntletRunFixture.resultVM) }
#endif
