/*
 * Purpose: Library tab (canvas 5a phone list / canvas 2c tablet
 *          master–detail) — H1 (phone only; the shell draws it on iPad), type
 *          chips, the Everything/Not done/Done toggle row with the live
 *          "N OPEN · N DONE" count, and the casebook rows (retired-done
 *          greyed below a divider). Hosts the `libraryPath` NavigationStack
 *          (F1 deferred tab-stack mounting to F4 — see RootShell's
 *          libraryDetailOpen chrome gate). The chip row/toggle row/rows list
 *          are factored into LibraryTypeChipRow/LibraryToggleRow/
 *          LibraryRowsList below so Task 5's LibraryMasterDetailView.swift
 *          (regular size class, canvas 2c) reuses them verbatim with
 *          select-on-tap instead of push.
 * Inputs: LibraryViewModel (default APIClient.shared via LibraryService); DEBUG
 *         `-LibraryFixtures` swaps in the FixtureLibraryService stub so
 *         screenshots need no dev server.
 * Outputs: none.
 * Run: shown by RootShell for DSTab.library.
 */

import SwiftUI

struct CasesListView: View {
    @State private var viewModel: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dsPalette) private var palette

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LibraryFixtures") {
            let fixtureVM = LibraryViewModel(service: LibraryFixtures.service)
            fixtureVM.fixtureDecorations = LibraryFixtures.decorations
            _viewModel = State(initialValue: fixtureVM)
        } else {
            _viewModel = State(initialValue: LibraryViewModel())
        }
        #else
        _viewModel = State(initialValue: LibraryViewModel())
        #endif
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { AppRouter.shared.libraryPath },
            set: { AppRouter.shared.libraryPath = $0 }
        )) {
            sizeClassBody
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    if case .caseDetail(let id) = route {
                        CaseDetailView(caseId: id)
                    }
                }
        }
    }

    @ViewBuilder
    private var sizeClassBody: some View {
        Group {
            if hSize == .regular {
                // F4 Task 5: tablet master–detail (canvas 2c, 1fr|470px split).
                LibraryMasterDetailView(viewModel: viewModel)
            } else {
                phoneList
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.type) { _, _ in
            // The type chip filters server-side (CaseQuery.caseType) — the
            // done toggle stays client-side over the already-loaded set, so
            // only a type change needs a reload (carry-in from Task 2 review).
            Task { await viewModel.load() }
        }
    }

    private var phoneList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LibraryTypeChipRow(viewModel: viewModel)
                    .padding(.top, 14)

                LibraryToggleRow(viewModel: viewModel)
                    .padding(.top, 9)

                LibraryRowsList(viewModel: viewModel) { libraryCase in
                    AppRouter.shared.go(to: .caseDetail(libraryCase.id))
                }
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Shared chip/toggle/rows components (phone list + Task 5 tablet
// master–detail's left column both bind these to the same LibraryViewModel).

/// Type chip row (All / Market entry / Profitability / M&A / Sizing) — active
/// chip = ink capsule fill, inactive = glassChip(). Tapping sets `vm.type`;
/// the caller (CasesListView.sizeClassBody) reloads on that change.
struct LibraryTypeChipRow: View {
    let viewModel: LibraryViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(LibraryType.allCases, id: \.self) { type in
                    chip(for: type)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chip(for type: LibraryType) -> some View {
        let active = viewModel.type == type
        let label = Button {
            viewModel.type = type
        } label: {
            Text(type.label)
                .font(.archivo(11.5, weight: 600))
                .foregroundStyle(active ? palette.onInk : palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
        }
        .buttonStyle(DSPressStyle())

        if active {
            label.background(Capsule().fill(palette.ink))
        } else {
            label.glassChip()
        }
    }
}

/// The `countLine` (left, kicker/muted) + Everything/Not done/Done text
/// toggles (right, active = ink+underline) over a bottom hairline.
struct LibraryToggleRow: View {
    let viewModel: LibraryViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.countLine)
                    .font(.archivo(9.5, weight: 600))
                    .tracking(9.5 * 0.14)
                    .tabularNumbers()
                    .foregroundStyle(palette.muted)
                Spacer()
                HStack(spacing: 14) {
                    ForEach(LibraryDone.allCases, id: \.self) { done in
                        doneToggle(done)
                    }
                }
            }
            .padding(.bottom, 9)

            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func doneToggle(_ done: LibraryDone) -> some View {
        let active = viewModel.done == done
        return Button {
            viewModel.done = done
        } label: {
            Text(done.label)
                .font(.archivo(11, weight: 600))
                .foregroundStyle(active ? palette.ink : palette.faint)
                .overlay(alignment: .bottom) {
                    if active {
                        Rectangle().fill(palette.ink).frame(height: 1).offset(y: 3)
                    }
                }
        }
        .buttonStyle(DSPressStyle())
    }
}

/// The casebook rows list (`LibraryRowView` per `.row`, `LibraryDividerRow`
/// per `.divider`, empty-state serif italic). `onRowTap` is push-to-detail on
/// phone, select-only on tablet (Task 5); `selectedID` drives the glass-chip
/// fill and is nil (no highlight) on phone.
struct LibraryRowsList: View {
    let viewModel: LibraryViewModel
    var selectedID: Int? = nil
    let onRowTap: (LibraryCase) -> Void
    @Environment(\.dsPalette) private var palette

    init(viewModel: LibraryViewModel, selectedID: Int? = nil, onRowTap: @escaping (LibraryCase) -> Void) {
        self.viewModel = viewModel
        self.selectedID = selectedID
        self.onRowTap = onRowTap
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.filteredRows) { row in
                switch row {
                case .row(let libraryCase):
                    LibraryRowView(row: libraryCase, isSelected: libraryCase.id == selectedID) {
                        onRowTap(libraryCase)
                    }
                case .divider(let label):
                    LibraryDividerRow(label: label)
                }
            }

            if viewModel.isEmpty {
                Text("Nothing here under these filters.")
                    .font(.serifVoice(14, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.vertical, 26)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 40)
    }
}

#Preview {
    CasesListView()
}
