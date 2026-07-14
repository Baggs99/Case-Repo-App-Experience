/*
 * Purpose: Candidate side of QR pairing (Task 14) — scans the interviewer's
 *          QR (VisionKit DataScannerViewController, QR-only), claims the
 *          token, and navigates into the created session.
 * Inputs: PairViewModel (default APIClient.shared). Camera access via
 *         NSCameraUsageDescription (ios/project.yml).
 * Outputs: none.
 * Run: pushed from SessionsView's "Start in-person session" entry point.
 *      MANUAL, DEVICE-ONLY CHECK: the simulator has no camera, so the
 *      actual scan (DataScannerViewController) can't run in CI/sim — verify
 *      the live scan on a physical device. claim(token:) itself is
 *      unit-tested in PairViewModelTests by passing a token directly.
 */

import SwiftUI
import VisionKit

struct PairScanView: View {
    @State private var viewModel = PairViewModel()

    var body: some View {
        content
            .navigationTitle("Scan to Join")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: sessionReadyBinding) {
                if let sessionId = viewModel.claimedSessionId {
                    SessionView(sessionId: sessionId)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            QRScannerRepresentable { code in
                Task { await viewModel.claim(token: code) }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                bottomOverlay
            }
        } else {
            ContentUnavailableView("Scanning Unavailable", systemImage: "camera.slash")
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        if viewModel.isLoading {
            ProgressView().padding()
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .foregroundStyle(.white)
                .padding()
                .background(.red.opacity(0.85), in: Capsule())
                .padding(.bottom, 24)
        }
    }

    private var sessionReadyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.claimedSessionId != nil },
            set: { _ in }
        )
    }
}

/// Wraps VisionKit's DataScannerViewController, restricted to QR codes, and
/// reports the first scanned payload string.
struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        // Guards against firing onScan more than once per view lifetime —
        // the scanner keeps recognizing the same code every frame.
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            guard !hasScanned, let item = addedItems.first,
                  case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue else { return }
            hasScanned = true
            onScan(payload)
        }
    }
}

#Preview {
    NavigationStack {
        PairScanView()
    }
}
