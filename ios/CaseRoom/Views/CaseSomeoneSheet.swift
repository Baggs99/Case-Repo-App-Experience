/*
 * Purpose: The "Case someone" glass sheet (canvas 3b `sheetSomeone3`) — the ONE
 *          glass card; inner content is FLAT (a filled "Scan their QR" ink
 *          capsule, hairline-separated rows, a serif gate note, underline
 *          Cancel; no icons). Scanning uses AVFoundation (AVCaptureMetadataOutput
 *          .qr) on device; on the simulator (no camera) or when camera access is
 *          denied, it falls back to an inline short-code text field + Pair.
 * Inputs: CaseSomeoneViewModel (live default, or the `-CaseFixtures` stub).
 * Outputs: none directly; VM side effects (pairClaim). claimedSessionID steers
 *          RootShell's session takeover; gatedRecapSessionID (defensive) pushes
 *          the interim recap stub — both wired here as interim navigation.
 * Run: presented from CaseTabView's `.sheet(item:)` `.caseSomeone` branch.
 */

import AVFoundation
import SwiftUI

struct CaseSomeoneSheet: View {
    @State private var viewModel: CaseSomeoneViewModel
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var manualCode = ""
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(viewModel: CaseSomeoneViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        card
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)   // canvas 22px 20px 18px
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSheet(cornerRadius: 34)                                       // §1 sheet recipe, canvas radius 34
            .padding(.horizontal, 10)                                          // canvas left/right:10
            .frame(maxHeight: .infinity, alignment: .bottom)                   // bottom-anchored card
            .presentationDetents([.height(440)])
            .presentationBackground(.clear)                                    // the glass IS the background
            .presentationDragIndicator(.hidden)
            .task { await viewModel.load() }
            // Interim navigation seams (F5 refits): a successful claim opens the
            // existing session; a recap gate (never expected for an interviewer
            // seat) is handled defensively by pushing the interim recap stub.
            .onChange(of: viewModel.claimedSessionID) { _, newValue in
                guard let id = newValue else { return }
                dismiss()
                AppRouter.shared.sessionTakeoverID = id
            }
            .onChange(of: viewModel.gatedRecapSessionID) { _, newValue in
                guard let id = newValue else { return }
                dismiss()
                AppRouter.shared.go(to: .recap(id))
            }
            .fullScreenCover(isPresented: $showScanner) {
                CaseSomeoneScanCover { code in
                    showScanner = false
                    Task { await viewModel.scanResult(code) }
                }
            }
    }

    // MARK: - Card content (flat)

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CASE SOMEONE")
                .font(.archivo(9.5, weight: 600)).tracking(0.16 * 9.5)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 14)

            // Additive prefill affordance (canvas `sheetSomeone3` has no case
            // field): the "case someone WITH THIS case" context surfaces as a
            // subtle muted line only when the F4 CTA carried a case title.
            if let title = viewModel.prefillCaseTitle {
                Text("Using this case: \(title)")
                    .font(.archivo(11.5, weight: 500))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.bottom, 12)
            }

            scanButton
                .padding(.bottom, showManualEntry ? 12 : 14)

            if showManualEntry {
                manualEntry
                    .padding(.bottom, 14)
            }

            openInvitesRow
                .padding(.vertical, 11)
                .overlay(hairline(0.1), alignment: .top)

            interviewerLogRow
                .padding(.top, 11).padding(.bottom, 16)
                .overlay(hairline(0.1), alignment: .top)

            Text("Interviewing is never gated — recaps only block your candidate seat.")
                .dsText(.serif(12, italic: true))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 6)
                .overlay(hairline(0.1), alignment: .top)

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.archivo(12.5, weight: 600)).underline()
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Scan their QR (filled ink capsule) + camera / manual fallback

    private var scanButton: some View {
        Button { beginScan() } label: {
            Text("Scan their QR")
                .font(.archivo(13.5, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
    }

    /// Present the AVFoundation scanner when a camera exists and is authorized;
    /// otherwise (simulator has none; user denied access) reveal the inline
    /// short-code fallback instead of crashing into a dead camera surface.
    private func beginScan() {
        guard AVCaptureDevice.default(for: .video) != nil else {
            showManualEntry = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { showScanner = true } else { showManualEntry = true }
                }
            }
        default:
            showManualEntry = true
        }
    }

    /// Inline short-code fallback (canvas has none — an additive graceful
    /// degradation for the simulator / denied-camera path). Flat: a hairline
    /// text field + an underline Pair action.
    private var manualEntry: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Enter their code", text: $manualCode)
                .font(.archivo(13.5, weight: 600))
                .foregroundStyle(palette.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(submitManualCode)
                .padding(.bottom, 6)
                .overlay(hairline(0.2), alignment: .bottom)
            Button(action: submitManualCode) {
                Text("Pair")
                    .font(.archivo(12.5, weight: 600)).underline()
                    .foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submitManualCode() {
        let code = manualCode
        Task { await viewModel.scanResult(code) }
    }

    // MARK: - Rows

    private var openInvitesRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open invites — \(viewModel.openInviteCount) waiting")
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(palette.ink)
                if let line = viewModel.firstInviteLine {
                    Text(line)
                        .font(.archivo(11.5, weight: 400))
                        .foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 8)
            if viewModel.hasNew {
                Text("NEW")
                    .font(.archivo(9, weight: 600)).tracking(0.12 * 9)
                    .foregroundStyle(palette.green)
            }
        }
    }

    private var interviewerLogRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your interviewer log")
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(palette.ink)
                if let line = viewModel.interviewerLogLine {
                    Text(line)
                        .font(.archivo(11.5, weight: 400))
                        .foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 8)
            Text("→")
                .font(.archivo(11, weight: 600))
                .foregroundStyle(palette.muted)
        }
    }

    private func hairline(_ opacity: Double) -> some View {
        Rectangle().fill(palette.ink.opacity(opacity)).frame(height: 1)
    }
}

/// Full-screen camera cover for the QR scan (device-only — the sheet only
/// presents this when a camera is available and authorized). Reports the first
/// decoded payload and carries a Cancel affordance.
private struct CaseSomeoneScanCover: View {
    let onScan: (String) -> Void
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            QRMetadataScanner(onScan: onScan)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.archivo(13.5, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(Capsule().fill(palette.ink))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }
}

/// AVFoundation QR scanner (AVCaptureMetadataOutput restricted to `.qr`). Fires
/// `onScan` once with the first decoded string. Device-only; the capture session
/// simply never yields metadata on the simulator (which is why the sheet routes
/// the simulator to the manual fallback before ever presenting this).
struct QRMetadataScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "caseroom.qr.scan")
        private var previewLayer: AVCaptureVideoPreviewLayer?
        // The scanner keeps recognizing the same code every frame — fire once.
        private var hasScanned = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            sessionQueue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let payload = object.stringValue else { return }
            hasScanned = true
            onScan?(payload)
        }
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground() }
        .sheet(isPresented: .constant(true)) {
            CaseSomeoneSheet(viewModel: .fixture())
        }
}
#endif
