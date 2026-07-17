/*
 * Purpose: Library tab (canvas 5a phone list) — H1, type chips, the
 *          Everything/Not done/Done toggle row with the live "N OPEN · N DONE"
 *          count, and the casebook rows (retired-done greyed below a divider).
 *          Hosts the `libraryPath` NavigationStack (F1 deferred tab-stack
 *          mounting to F4 — see RootShell's libraryDetailOpen chrome gate).
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
        if hSize == .regular {
            // F4 Task 5: tablet master-detail (canvas 2c, 1fr|470px split).
            // The phone list renders here in the interim — acceptable per
            // Task 3 scope (do not build the 2-column layout this task).
            phoneList
        } else {
            phoneList
        }
    }

    private var phoneList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                typeChipRow
                    .padding(.top, 14)

                toggleRow
                    .padding(.top, 9)

                rowsList
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .task { await viewModel.load() }
        .onChange(of: viewModel.type) { _, _ in
            // The type chip filters server-side (CaseQuery.caseType) — the
            // done toggle stays client-side over the already-loaded set, so
            // only a type change needs a reload (carry-in from Task 2 review).
            Task { await viewModel.load() }
        }
    }

    private var typeChipRow: some View {
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

    private var toggleRow: some View {
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

    private var rowsList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.filteredRows) { row in
                switch row {
                case .row(let libraryCase):
                    LibraryRowView(row: libraryCase) {
                        AppRouter.shared.go(to: .caseDetail(libraryCase.id))
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
