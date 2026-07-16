/*
 * Purpose: Propose-now sheet — pick a case (searchable, via CasesViewModel) and
 *          a role, optionally add a note, and send an instant "now" proposal to
 *          a classmate, then show a brief confirmation and dismiss. Reached from
 *          a Today free-now row or a free_now push (deep-linkable by user id).
 * Inputs: toUser (recipient id) + optional toName for display; CasesViewModel
 *         (default APIClient.shared) for the case list; APIClient for send.
 * Outputs: a POST /api/proposals on send (side effect only).
 * Run: ProposeNowView(toUser: 7) — presented as a .sheet.
 */

import SwiftUI

struct ProposeNowView: View {
    let toUser: Int
    var toName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var role: ProposalRole = .interviewer
    @State private var selectedCase: CaseSummary?
    @State private var message: String = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    enum ProposalRole: String, CaseIterable, Identifiable {
        case interviewer, candidate
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            Group {
                if didSend {
                    confirmation
                } else {
                    form
                }
            }
            .navigationTitle("Propose now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                            .disabled(selectedCase == nil || isSending)
                    }
                }
            }
            .task(id: didSend) {
                guard didSend else { return }
                try? await Task.sleep(for: .seconds(1.4))
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        Form {
            Section("Send to") {
                Label(toName ?? "Classmate", systemImage: "person.crop.circle")
            }

            Section("Your role") {
                Picker("Your role", selection: $role) {
                    ForEach(ProposalRole.allCases) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Case") {
                NavigationLink {
                    CasePickerView { selectedCase = $0 }
                } label: {
                    if let selectedCase {
                        Text(selectedCase.caseTitle)
                    } else {
                        Text("Choose a case").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Message") {
                TextField("Add a note (optional)", text: $message, axis: .vertical)
                    .lineLimit(1...3)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Proposal sent")
                .font(.title3.weight(.semibold))
            Text("You'll be notified if \(toName ?? "your classmate") accepts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send() async {
        guard let selectedCase else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await APIClient.shared.createProposal(
                toUserId: toUser,
                caseId: selectedCase.id,
                fromRole: role.rawValue,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message
            )
            didSend = true
        } catch {
            errorMessage = "Couldn't send your proposal. Try again."
        }
    }
}

// Searchable case list reusing CasesViewModel; selecting a row hands the case
// back and pops. Mirrors CasesListView's debounced search idiom.
private struct CasePickerView: View {
    let onSelect: (CaseSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CasesViewModel()

    private struct FilterKey: Equatable { var query: String }

    var body: some View {
        content
            .navigationTitle("Choose a case")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Search cases")
            .task(id: FilterKey(query: viewModel.query)) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await viewModel.load()
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
                Button {
                    onSelect(caseSummary)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caseSummary.caseTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let difficulty = caseSummary.difficulty {
                            Text(difficulty)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ProposeNowView(toUser: 7, toName: "Bob Dev")
}
