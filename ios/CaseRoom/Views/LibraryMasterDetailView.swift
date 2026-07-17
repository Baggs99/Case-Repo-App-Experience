/*
 * Purpose: Tablet master–detail Library (canvas 2c) — regular-size-class body
 *          for CasesListView: a 1fr | 470pt grid divided by a hairline, left
 *          reuses the phone's LibraryTypeChipRow/LibraryToggleRow/
 *          LibraryRowsList with select-on-tap (no push, no H1 — RootShell
 *          draws the centered "Library" tab label on .regular), right is an
 *          always-visible CaseDetailContent(layout: .tablet) for the
 *          selection (falls back to the first row via
 *          LibraryViewModel.selectedCase). Bottom padding clears the 560pt
 *          floating tab bar.
 * Inputs: LibraryViewModel — owned and `.load()`ed by CasesListView; this
 *         view only mutates `viewModel.selectedID` on row tap.
 * Outputs: none.
 * Run: `LibraryMasterDetailView(viewModel:)` from CasesListView.sizeClassBody
 *      when `hSize == .regular`.
 */

import SwiftUI

struct LibraryMasterDetailView: View {
    let viewModel: LibraryViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            masterColumn
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.trailing, 28)
                .overlay(alignment: .trailing) {
                    // Canvas 2c: `border-right:1px solid #C9D2DF` on the left
                    // column — palette.hairline is the exact F0 token match.
                    Rectangle().fill(palette.hairline).frame(width: 1)
                }

            detailColumn
                .frame(width: 470, alignment: .top)
                .padding(.leading, 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Left: chips + toggle/count + rows (select-on-tap, no push, no H1)

    private var masterColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryTypeChipRow(viewModel: viewModel)

            LibraryToggleRow(viewModel: viewModel)
                .padding(.top, 10)

            ScrollView {
                LibraryRowsList(
                    viewModel: viewModel,
                    selectedID: viewModel.selectedID
                ) { libraryCase in
                    viewModel.selectedID = libraryCase.id
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Right: always-visible detail for the selection

    @ViewBuilder
    private var detailColumn: some View {
        ScrollView {
            if let selected = viewModel.selectedCaseWithHistory {
                CaseDetailContent(layout: .tablet, libraryCase: selected)
            }
        }
        .scrollIndicators(.hidden)
    }
}

#if DEBUG
#Preview {
    let vm = LibraryViewModel(service: LibraryFixtures.service)
    vm.fixtureDecorations = LibraryFixtures.decorations
    return LibraryMasterDetailView(viewModel: vm)
        .task { await vm.load() }
}
#endif
