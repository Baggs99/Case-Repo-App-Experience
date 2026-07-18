/*
 * Purpose: The "Get cased now" glass sheet (canvas 3b `sheetNow3`) — the ONE
 *          glass card; inner content is FLAT (a real QR, hairline-separated
 *          rows, underline secondary actions, no icons). Header kicker, a QR +
 *          in-person pairing line (short-code fallback), the free-right-now
 *          board (Ping each), an "Anyone — send a link" copy row, and Cancel.
 *          QR is CoreImage (CIQRCodeGenerator via the shared QRCode helper) —
 *          a rendered data matrix, not an icon.
 * Inputs: GetCasedNowViewModel (live default, or the `-CaseFixtures` stub).
 * Outputs: none directly; VM side effects (now-invite, clipboard) + toasts.
 * Run: presented from CaseTabView's `.sheet(item:)` `.getCased` branch.
 */

import SwiftUI

struct GetCasedNowSheet: View {
    @State private var viewModel: GetCasedNowViewModel
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(viewModel: GetCasedNowViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        card
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)   // canvas 22px 20px 18px
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSheet(cornerRadius: 34)                                       // §1 sheet recipe, canvas radius 34
            .padding(.horizontal, 10)                                          // canvas left/right:10
            .frame(maxHeight: .infinity, alignment: .bottom)                   // bottom-anchored card
            .dsToast(item: toastBinding)
            .presentationDetents([.height(520)])
            .presentationBackground(.clear)                                    // the glass IS the background
            .presentationDragIndicator(.hidden)
            .task { await viewModel.load() }
    }

    // MARK: - Card content (flat)

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GET CASED NOW")
                .font(.archivo(9.5, weight: 600)).tracking(0.16 * 9.5)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 14)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.bottom, 12)
            }

            qrRow
                .padding(.bottom, 16)
                .overlay(hairline(0.12), alignment: .bottom)
                .padding(.bottom, 14)

            Text("REMOTE — FREE RIGHT NOW")
                .font(.archivo(9.5, weight: 600)).tracking(0.15 * 9.5)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 8)

            ForEach(Array(viewModel.liveNow.enumerated()), id: \.element.id) { index, row in
                boardRow(row)
                    .overlaidTopHairline(index > 0 ? hairline(0.1) : nil)
            }

            linkRow
                .padding(.top, 9).padding(.bottom, 14)
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

    // MARK: - QR + in-person pairing line

    private var qrRow: some View {
        HStack(alignment: .center, spacing: 14) {
            qrSquare
            VStack(alignment: .leading, spacing: 2) {
                Text("In person — show this")
                    .font(.archivo(15, weight: 700))
                    .foregroundStyle(palette.ink)
                Text("Their scan pairs you instantly. Code \(viewModel.shortCode) works too.")
                    .dsText(.serif(12.5, italic: true))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A crisp, real QR (CIQRCodeGenerator M, integer-scaled nearest-neighbor
    /// via the shared QRCode helper) encoding the pinned pairURL. Rendered
    /// ink-on-white; `.interpolation(.none)` keeps the modules sharp.
    @ViewBuilder
    private var qrSquare: some View {
        if let image = QRCode.image(from: viewModel.pairURL) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 86, height: 86)
        } else {
            Color.clear.frame(width: 86, height: 86)
        }
    }

    // MARK: - Free-right-now board rows

    private func boardRow(_ row: GetCasedNowViewModel.LiveNowRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            (
                Text(row.name)
                    .font(.archivo(13.5, weight: 600)).foregroundStyle(palette.ink)
                + Text(Self.boardSuffix(school: row.school, minutesFree: row.minutesFree))
                    .font(.archivo(11, weight: 400)).foregroundStyle(palette.muted)
            )
            Spacer(minLength: 8)
            Button { Task { await viewModel.ping(userId: row.id) } } label: {
                Text("Ping")
                    .font(.archivo(12.5, weight: 600)).underline()
                    .foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
    }

    private var linkRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Anyone — send a link")
                .font(.archivo(13.5, weight: 600))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            Button { viewModel.copyLink() } label: {
                Text("Copy link")
                    .font(.archivo(12.5, weight: 600)).underline()
                    .foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    /// "· \(school) · N min free" — the school segment is omitted when the
    /// availability payload carries none (canvas: "· Wharton · 45 min free").
    private static func boardSuffix(school: String?, minutesFree: Int) -> String {
        if let school { return " · \(school) · \(minutesFree) min free" }
        return " · \(minutesFree) min free"
    }

    private func hairline(_ opacity: Double) -> some View {
        Rectangle().fill(palette.ink.opacity(opacity)).frame(height: 1)
    }

    private var toastBinding: Binding<String?> {
        Binding(get: { viewModel.toastMessage }, set: { viewModel.toastMessage = $0 })
    }
}

private extension View {
    /// Apply a top-hairline overlay only when one is provided (first board row
    /// gets none; the rest are separated by a hairline — canvas `sheetNow3`).
    @ViewBuilder
    func overlaidTopHairline<H: View>(_ hairline: H?) -> some View {
        if let hairline {
            overlay(hairline, alignment: .top)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground() }
        .sheet(isPresented: .constant(true)) {
            GetCasedNowSheet(viewModel: .fixture())
        }
}
#endif
