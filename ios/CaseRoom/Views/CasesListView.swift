/*
 * Purpose: Cases tab — searchable, difficulty-filterable list of case
 *          summaries backed by CasesViewModel.
 * Inputs: CasesViewModel (default APIClient.shared via CasesService).
 * Outputs: none.
 * Run: shown as a tab by RootTabView.
 */

import SwiftUI

private struct CasesFilterKey: Equatable {
    var query: String
    var difficulty: String?
}

struct CasesListView: View {
    @State private var viewModel = CasesViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cases")
                .navigationDestination(for: Int.self) { caseId in
                    CaseDetailView(caseId: caseId)
                }
                .searchable(text: $viewModel.query, prompt: "Search cases")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Difficulty", selection: $viewModel.difficulty) {
                                Text("All").tag(String?.none)
                                Text("Easy").tag(String?.some("Easy"))
                                Text("Medium").tag(String?.some("Medium"))
                                Text("Hard").tag(String?.some("Hard"))
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .task(id: CasesFilterKey(query: viewModel.query, difficulty: viewModel.difficulty)) {
                    // Debounce so typing doesn't fire a request per keystroke.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await viewModel.load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(errorMessage, systemImage: "wifi.slash")
        } else if viewModel.results.isEmpty {
            ContentUnavailableView("No Cases", systemImage: "folder")
        } else {
            List(viewModel.results) { caseSummary in
                NavigationLink(value: caseSummary.id) {
                    CaseRow(caseSummary: caseSummary)
                }
            }
        }
    }
}

private struct CaseRow: View {
    let caseSummary: CaseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caseSummary.caseTitle)
                .font(.headline)
            HStack(spacing: 8) {
                if let difficulty = caseSummary.difficulty {
                    Text(difficulty)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color("BrandAccent").opacity(0.15))
                        .foregroundStyle(Color("BrandAccent"))
                        .clipShape(Capsule())
                }
                if let secondary = secondaryLine {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var secondaryLine: String? {
        switch (caseSummary.industryDisplay, caseSummary.firm) {
        case let (industry?, firm?):
            return "\(industry) · \(firm)"
        case let (industry?, nil):
            return industry
        case let (nil, firm?):
            return firm
        default:
            return nil
        }
    }
}

#Preview {
    CasesListView()
}
