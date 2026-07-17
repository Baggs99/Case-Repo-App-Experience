/*
 * Purpose: Timeline-detail screen (canvas 7b) — the spelled-out headline, the
 *          F0 SteppedTimeline, per-firm readiness rows, an add-a-firm chip
 *          wrap, and the passed-deadline interview-outcome prompt flow.
 * Inputs: TimelineDetailViewModel (injectable; DEBUG fixture init for shots).
 * Outputs: none (navigation back via dismiss(); all writes live in the VM).
 * Run: pushed onto Home's NavigationStack via AppRoute.timelineDetail.
 */

import SwiftUI

struct TimelineDetailView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TimelineDetailViewModel

    // Injectable VM (default = live). The DEBUG -F2Timeline / -F2TimelinePromptNoOffer
    // hatches inject a fixture-backed VM so simctl can capture a populated screen.
    @MainActor
    init(viewModel: TimelineDetailViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? TimelineDetailViewModel())
    }

    var body: some View {
        ZStack {
            DSBackground()
            if viewModel.detail == nil {
                ProgressView().tint(palette.ink)
            } else {
                content
            }
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                topRow
                headline
                SteppedTimeline(firms: viewModel.timelineFirms)
                readinessSection
                addFirmSection
                passedSection
                Color.clear.frame(height: 120)   // room behind the tab bar
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .dsHeaderFade()
    }

    // MARK: - Header

    private var topRow: some View {
        Button {
            dismiss()
        } label: {
            BackPill(label: "Home", context: "TIMELINE")
        }
        .buttonStyle(.plain)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.headlineDays).dsText(.h1Tab).foregroundStyle(palette.ink)
            Text("\(viewModel.nextRiserName) is the next riser. Everything paces to it.")
                .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
        }
    }

    // MARK: - Readiness rows

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("READINESS, PER FIRM").dsText(.kicker).foregroundStyle(palette.muted)
            VStack(spacing: 0) {
                let firms = viewModel.readinessFirms
                let added = viewModel.addedRows
                ForEach(Array(firms.enumerated()), id: \.element.id) { index, firm in
                    readinessRow(firm)
                    if index < firms.count - 1 || !added.isEmpty {
                        Divider().overlay(palette.hairlineSoft)
                    }
                }
                ForEach(Array(added.enumerated()), id: \.element.id) { index, entry in
                    setDateRow(entry)
                    if index < added.count - 1 {
                        Divider().overlay(palette.hairlineSoft)
                    }
                }
            }
        }
    }

    private func readinessRow(_ firm: TimelineFirmDetail) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(firm.name) — \(TimelineDetailViewModel.formattedDate(firm.deadline?.deadlineDate ?? ""))")
                    .dsText(.rowTitle).foregroundStyle(palette.ink)
                Text(viewModel.secondaryLine(for: firm)).dsText(.meta).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 12)
            Text(TimelineDetailViewModel.tagLabel(firm.readinessTag))
                .dsText(.kicker)
                .foregroundStyle(firm.readinessTag == "on_track" ? palette.green : palette.muted)
        }
        .padding(.vertical, 12)
    }

    private func setDateRow(_ entry: FirmCatalogEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).dsText(.rowTitle).foregroundStyle(palette.ink)
                Text("Deadline unknown — set it to join the line").dsText(.meta).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 12)
            // INERT: B7 has no set-user-deadline endpoint (backend follow-up).
            Button {} label: {
                Text("Set date").dsText(.rowTitle).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Add a firm

    private var addFirmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD A FIRM").dsText(.kicker).foregroundStyle(palette.muted)
            FlowLayout(spacing: 8) {
                ForEach(viewModel.addableChips) { entry in
                    Button {
                        Task { await viewModel.addFirm(entry.firmId) }
                    } label: {
                        Text(entry.name).dsText(.rowTitle).foregroundStyle(palette.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(DSPressStyle())
                    .glassChipFlat()
                }
            }
        }
    }

    // MARK: - Passed-deadline prompt

    @ViewBuilder
    private var passedSection: some View {
        if let firm = viewModel.passedPrompt {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.passedHeader(firm)).dsText(.kicker).foregroundStyle(palette.muted)
                    Spacer(minLength: 12)
                    Text("\(viewModel.daysAgo(firm)) DAYS AGO").dsText(.kicker).foregroundStyle(palette.faint)
                }
                promptBody(firm)
            }
            .animation(DSMotion.sheetCurve, value: viewModel.promptStage)
        }
    }

    @ViewBuilder
    private func promptBody(_ firm: TimelineFirmDetail) -> some View {
        switch viewModel.promptStage {
        case .initial:
            VStack(alignment: .leading, spacing: 14) {
                Text("Did you interview?").dsText(.rowTitleStrong).foregroundStyle(palette.ink)
                HStack(spacing: 10) {
                    promptButton("Yes") { Task { await viewModel.answerInterviewed(true) } }
                    promptButton("No") { Task { await viewModel.answerInterviewed(false) } }
                }
            }
        case .interviewed:
            VStack(alignment: .leading, spacing: 14) {
                Text("How did it go?").dsText(.rowTitleStrong).foregroundStyle(palette.ink)
                HStack(spacing: 10) {
                    promptButton("Offer") { Task { await viewModel.recordOutcome("offer") } }
                    promptButton("No offer") { Task { await viewModel.recordOutcome("no_offer") } }
                    promptButton("Waiting") { Task { await viewModel.recordOutcome("waiting") } }
                }
            }
            .transition(.dsRise)
        case .result(let result):
            resultCard(result)
                .transition(.dsRise)
        }
    }

    private func promptButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).dsText(.rowTitle).foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .buttonStyle(DSPressStyle())
        .glassChipFlat()
    }

    @ViewBuilder
    private func resultCard(_ result: FirmResult) -> some View {
        switch result.outcome {
        case "offer":
            VStack(alignment: .leading, spacing: 8) {
                Text("OFFER — WELL EARNED").dsText(.kicker).foregroundStyle(palette.green)
                Text("Marked on your record. Your remaining firms stay on the line; interviewers " +
                     "will see a candidate with an offer in hand.")
                    .dsText(.serif(13, italic: true)).foregroundStyle(palette.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(palette.green.opacity(0.07)))
            .overlay(Rectangle().strokeBorder(palette.green, lineWidth: 1))

        case "no_offer":
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(palette.ink).frame(height: 2)
                if let reweight = result.reweight {
                    Text(viewModel.noOfferBody(reweight)).dsText(.serif(13, italic: true)).foregroundStyle(palette.ink)
                    Text(viewModel.noOfferKicker(reweight)).dsText(.kicker).foregroundStyle(palette.muted)
                }
            }

        case "waiting":
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(palette.hairline)
                Text("Fingers off the refresh. We'll ask again in a week — the line holds its shape till then.")
                    .dsText(.serif(13, italic: true)).foregroundStyle(palette.muted)
            }

        case "didnt_interview":
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(palette.hairline)
                Text(viewModel.droppedBody).dsText(.serif(13, italic: true)).foregroundStyle(palette.muted)
            }

        default:
            EmptyView()
        }
    }
}

/// A minimal left-to-right wrap layout for the add-a-firm chip cloud (no shared
/// DS flow-layout primitive exists yet; kept private/screen-local).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                measuredWidth = max(measuredWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        measuredWidth = max(measuredWidth, rowWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : measuredWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
/// Screenshot/preview-only fixture in the live API model shapes (distinct from
/// PreviewFixtures.swift's `TimelineFirm`-only persona data): the July-16 phone
/// persona (Decisions §3) re-expressed as a TimelineDetail + firm catalog, so
/// -F2Timeline / -F2TimelinePromptNoOffer and #Preview can inject it directly.
enum PreviewTimelineFixture {
    static let detail = TimelineDetail(
        asOf: "2026-07-16",
        readiness: TimelineReadiness(label: "needs_work", ready: false, focusDimension: "Market sizing",
                                      recentCaseCount: 5, threshold: 6.0, minCases: 3),
        firms: [
            TimelineFirmDetail(
                firmId: 1, name: "McKinsey", slug: "mckinsey", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-12", region: "Americas",
                                        isEstimate: false, daysRemaining: 58, passed: false),
                readinessTag: "on_track", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 2, name: "BCG", slug: "bcg", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-09-30", region: "Americas",
                                        isEstimate: false, daysRemaining: 76, passed: false),
                readinessTag: "focus", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 3, name: "Bain", slug: "bain", status: "tracked", addedAt: "2026-06-01",
                deadline: FirmDeadline(cycleLabel: "Fall", deadlineDate: "2026-10-08", region: "Americas",
                                        isEstimate: true, daysRemaining: 84, passed: false),
                readinessTag: "early", prompt: FirmPrompt(show: false)),
            TimelineFirmDetail(
                firmId: 4, name: "Roland Berger", slug: "roland-berger", status: "tracked", addedAt: "2026-05-01",
                deadline: FirmDeadline(cycleLabel: "Summer", deadlineDate: "2026-07-02", region: "Americas",
                                        isEstimate: false, daysRemaining: -14, passed: true),
                readinessTag: "on_track", prompt: FirmPrompt(show: true)),
        ])

    static let catalog: [FirmCatalogEntry] = [
        FirmCatalogEntry(firmId: 1, name: "McKinsey", slug: "mckinsey", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 2, name: "BCG", slug: "bcg", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 3, name: "Bain", slug: "bain", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 4, name: "Roland Berger", slug: "roland-berger", tracked: true, nextDeadline: nil),
        FirmCatalogEntry(firmId: 5, name: "Deloitte", slug: "deloitte", tracked: false, nextDeadline: nil),
        FirmCatalogEntry(firmId: 6, name: "EY-Parthenon", slug: "ey-parthenon", tracked: false, nextDeadline: nil),
        FirmCatalogEntry(firmId: 7, name: "Oliver Wyman", slug: "oliver-wyman", tracked: false, nextDeadline: nil),
    ]

    /// The no_offer result card fixture — Roland Berger reweighting the plan.
    static let noOfferResult = FirmResult(
        outcome: "no_offer", status: "rejected",
        reweight: Reweight(focusDimension: "Market sizing", suggestedDrillType: "mental_math",
                            extraCases: [101, 205]),
        snoozeUntil: nil, resultRecordedAt: nil, dropped: nil)
}

#Preview {
    TimelineDetailView(viewModel: .init(fixtureDetail: PreviewTimelineFixture.detail,
                                         fixtureCatalog: PreviewTimelineFixture.catalog))
}
#endif
