/*
 * Purpose: Interviewer side of QR pairing (Task 14) — pick a case, mint a
 *          pairing token, show it as a QR code, and wait for the
 *          candidate's scan to create the session, then navigate in.
 * Inputs: PairViewModel (default APIClient.shared); CasesViewModel (P1's
 *         Cases browse) for case selection.
 * Outputs: none.
 * Run: pushed from SessionsView's "Start in-person session" entry point.
 */

import SwiftUI

struct PairCreateView: View {
    @State private var viewModel = PairViewModel()
    @State private var casesViewModel = CasesViewModel()

    var body: some View {
        content
            .navigationTitle("Create Pairing Code")
            .navigationBarTitleDisplayMode(.inline)
            .task { await casesViewModel.load() }
            .onDisappear { viewModel.stopPolling() }
            .navigationDestination(isPresented: sessionReadyBinding) {
                if let sessionId = viewModel.readySessionId {
                    SessionView(sessionId: sessionId)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.qrImage != nil {
            waitingContent
        } else {
            casePicker
        }
    }

    private var casePicker: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(casesViewModel.results) { caseSummary in
                Button {
                    Task { await viewModel.create(caseId: caseSummary.id) }
                } label: {
                    Text(caseSummary.caseTitle)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    private var waitingContent: some View {
        VStack(spacing: 20) {
            if let qrImage = viewModel.qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .accessibilityLabel("Pairing QR code")
            }
            Text("Waiting for your partner to scan…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var sessionReadyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.readySessionId != nil },
            set: { _ in }
        )
    }
}

#Preview {
    NavigationStack {
        PairCreateView()
    }
}
