/*
 * Purpose: Candidate's exhibit strip — shows each exhibit locked until its
 *          reveal key arrives, then decrypts and displays it.
 * Inputs: sessionId; SessionService (default APIClient.shared).
 * Outputs: none.
 * Run: pushed for the candidate once a session's state is "live". Wiring
 *      inbound .reveal SignalMessages from the session's WS into
 *      viewModel.handleReveal(exhibitId:keyB64:) lands in a later task.
 */

import SwiftUI

struct CandidateLiveView: View {
    @State private var viewModel: ExhibitsViewModel

    init(sessionId: Int, service: SessionService = APIClient.shared) {
        _viewModel = State(initialValue: ExhibitsViewModel(sessionId: sessionId, service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.exhibits, id: \.exhibitId) { exhibit in
                    exhibitCard(exhibit)
                }
            }
            .padding()
        }
        .navigationTitle("Exhibits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func exhibitCard(_ exhibit: ExhibitMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exhibit #\(exhibit.idx + 1)")
                .font(.headline)
            switch viewModel.state(for: exhibit.exhibitId) {
            case .locked:
                lockedPlaceholder
            case .revealed(let imageData):
                revealedImage(imageData)
            }
        }
    }

    private var lockedPlaceholder: some View {
        ContentUnavailableView("Locked", systemImage: "lock.fill")
            .foregroundStyle(Color("BrandAccent"))
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func revealedImage(_ data: Data) -> some View {
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ContentUnavailableView("Couldn't display this exhibit", systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview {
    NavigationStack {
        CandidateLiveView(sessionId: 1)
    }
}
