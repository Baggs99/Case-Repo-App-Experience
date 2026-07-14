/*
 * Purpose: Renders a pairing token as a scannable QR code image.
 * Inputs: the string to encode (a pairing token).
 * Outputs: none (pure function; returns a UIImage).
 * Run: QRCode.image(from: pairToken.token) from PairCreateView.
 */

import CoreImage.CIFilterBuiltins
import UIKit

enum QRCode {
    /// CIFilter's raw QR output is only a few points per module, which
    /// scans poorly on a phone screen — scale it up with nearest-neighbor
    /// (no interpolation) so the modules stay crisp.
    private static let scale: CGFloat = 10

    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
