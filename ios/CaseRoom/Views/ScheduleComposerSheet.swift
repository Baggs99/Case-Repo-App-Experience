/*
 * Purpose: The "Schedule later" composer glass sheet (canvas 3b `sheetLater3`) —
 *          the ONE glass card; inner content is a proposal builder: a WHO wrap
 *          row of selectable glass chips (one per connection), a WHEN wrap row
 *          of 4 quick-pick chips (Now / 1h / Tonight 8pm / Pick a time — the
 *          last reveals a compact DatePicker), a CASE column of flat glass
 *          option rows (Interviewer decides ⟂ Request: <rec>), a filled ink
 *          "Send the proposal" capsule, a serif calendar note, and underline
 *          Cancel. The sheet is the only glass hero; the WHO/WHEN chips use the
 *          §1 glass-CHIP recipe (chrome), CASE rows are flat glass buttons.
 * Inputs: ScheduleComposerViewModel (live default, or the `-CaseFixtures` stub).
 * Outputs: none directly; VM side effect (sendScheduledProposal) + a toast.
 * Run: presented from CaseTabView's `.sheet(item:)` `.schedule` branch.
 */

import SwiftUI

struct ScheduleComposerSheet: View {
    @State private var viewModel: ScheduleComposerViewModel
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(viewModel: ScheduleComposerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        // ScrollView wrap (T5-M3 fix): the fixed 560pt detent clips on shorter
        // devices once "Pick a time" reveals the inline DatePicker row — scroll
        // the card's content instead of growing the detent, so the sheet still
        // reads as the bottom-anchored glass card at any content height.
        ScrollView {
            card
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)   // canvas 22px 20px 18px
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .glassSheet(cornerRadius: 34)                                       // §1 sheet recipe, canvas radius 34
        .padding(.horizontal, 10)                                          // canvas left/right:10
        .frame(maxHeight: .infinity, alignment: .bottom)                   // bottom-anchored card
        .dsToast(item: toastBinding)
        .presentationDetents([.height(560)])
        .presentationBackground(.clear)                                    // the glass IS the background
        .presentationDragIndicator(.hidden)
        .task { await viewModel.load() }
        // A successful send toasts "Proposal sent", then dismisses.
        .onChange(of: viewModel.sent) { _, newValue in
            if newValue { dismiss() }
        }
    }

    // MARK: - Card content (flat)

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCHEDULE FOR LATER — A PROPOSAL")
                .font(.archivo(9.5, weight: 600)).tracking(0.16 * 9.5)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 14)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.bottom, 12)
            }

            whoSection
            whenSection
            caseSection

            sendButton

            Text("Accept · counter once · decline. The app is the calendar, not the conversation.")
                .dsText(.serif(11.5, italic: true))
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 10).padding(.bottom, 4)

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.archivo(12.5, weight: 600)).underline()
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - WHO — selectable glass chips (one per connection)

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionKicker("WHO")
            if viewModel.who.isEmpty {
                // Undesigned empty state (live, no connections) — token-styled.
                Text("No connections yet")
                    .dsText(.serif(12, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 14)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.who) { chip in
                        selectableChip(
                            label: chip.name,
                            selected: viewModel.selectedWhoID == chip.id
                        ) { viewModel.selectedWhoID = chip.id }
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - WHEN — 4 quick-pick chips (Pick a time reveals a DatePicker)

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionKicker("WHEN")
            FlowLayout(spacing: 6) {
                ForEach(ScheduleComposerViewModel.WhenPick.allCases, id: \.self) { pick in
                    selectableChip(
                        label: pick.label,
                        selected: viewModel.selectedWhen == pick
                    ) { viewModel.selectedWhen = pick }
                }
            }
            .padding(.bottom, viewModel.selectedWhen == .pickTime ? 10 : 14)

            if viewModel.selectedWhen == .pickTime {
                DatePicker("", selection: $viewModel.pickTime)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(palette.ink)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - CASE — flat glass option rows (Interviewer decides ⟂ Request:[rec])

    private var caseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionKicker("CASE")
            VStack(spacing: 6) {
                ForEach(viewModel.caseOptions) { option in
                    caseRow(option)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func caseRow(_ option: ScheduleComposerViewModel.CaseOption) -> some View {
        let selected = viewModel.selectedCase == option
        let tag = caseTag(option)
        return Button { viewModel.selectedCase = option } label: {
            HStack(spacing: 8) {
                Text(option.label)
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(tag.text)
                    .font(.archivo(9, weight: 600)).tracking(0.1 * 9)
                    .foregroundStyle(tag.color)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .glassChipFlat()                                          // canvas rgba(255,255,255,.5) flat glass
            .overlay(
                Capsule().strokeBorder(
                    selected ? palette.ink : Color.clear, lineWidth: 1.5
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send the proposal (the ONE filled button)

    private var sendButton: some View {
        Button { Task { await viewModel.send() } } label: {
            Text("Send the proposal")
                .font(.archivo(13.5, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
        .opacity(viewModel.canSend ? 1 : 0.4)                         // dimmed when incomplete
        .disabled(!viewModel.canSend)
    }

    // MARK: - Shared bits (selectable chip mirrors LibraryTypeChipRow's idiom)

    private func sectionKicker(_ text: String) -> some View {
        Text(text)
            .font(.archivo(9.5, weight: 600)).tracking(0.15 * 9.5)
            .foregroundStyle(palette.muted)
            .padding(.bottom, 8)
    }

    /// Selected chip = ink capsule fill (onInk text); unselected = glass chip
    /// (ink text) — the sanctioned §1 glass-CHIP recipe for chrome chips.
    @ViewBuilder
    private func selectableChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let content = Button(action: action) {
            Text(label)
                .font(.archivo(12, weight: 600))
                .foregroundStyle(selected ? palette.onInk : palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 36)
        }
        .buttonStyle(DSPressStyle())

        if selected {
            content.background(Capsule().fill(palette.ink))
        } else {
            content.glassChip()
        }
    }

    /// The CASE-row trailing tag (canvas has generic `o.tagText`/`o.tag`): a muted
    /// "DEFAULT" on Interviewer decides, a single green "FOR YOU" on the Request
    /// row (keeps greens ≤1). Documented deviation — the exact tag text isn't
    /// pinned in the canvas.
    private func caseTag(_ option: ScheduleComposerViewModel.CaseOption) -> (text: String, color: Color) {
        switch option {
        case .interviewerDecides: return ("DEFAULT", palette.muted)
        case .request: return ("FOR YOU", palette.green)
        }
    }

    private var toastBinding: Binding<String?> {
        Binding(get: { viewModel.toastMessage }, set: { viewModel.toastMessage = $0 })
    }
}

// MARK: - FlowLayout — a dependency-free wrap row (iOS 17 Layout protocol) for
// the WHO/WHEN chips, which wrap when they exceed the sheet width (canvas
// `flex-wrap:wrap`, gap 6).

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows = layout(subviews: subviews, maxWidth: maxWidth)
        // Height = last row's bottom.
        let height = rows.last.map { $0.y + $0.height } ?? 0
        rows.removeAll()
        return CGSize(width: maxWidth == .infinity ? 0 : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        for row in rows {
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
            }
        }
    }

    private struct RowItem { let index: Int; let x: CGFloat }
    private struct Row { let y: CGFloat; let height: CGFloat; let items: [RowItem] }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var items: [RowItem] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row(y: y, height: rowHeight, items: items))
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                items = []
            }
            items.append(RowItem(index: index, x: x))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !items.isEmpty {
            rows.append(Row(y: y, height: rowHeight, items: items))
        }
        return rows
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground() }
        .sheet(isPresented: .constant(true)) {
            ScheduleComposerSheet(viewModel: .fixture())
        }
}
#endif
