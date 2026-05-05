import Foundation
#if canImport(UIKit)
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

// MARK: - TwoFactorQRGenerator
// Pure static helper — no state, no network, no storage.
// Converts an otpauth:// URI into a UIImage using CoreImage CIFilter.

public enum TwoFactorQRGenerator: Sendable {

    /// Generate a QR code UIImage from an otpauth:// URI.
    /// - Parameters:
    ///   - uri:  The full `otpauth://totp/…` string.
    ///   - size: Desired output size in points (square).
    /// - Returns: A UIImage, or nil if CIFilter or CGImage creation failed.
    #if canImport(UIKit)
    public static func qrImage(from uri: String, size: CGSize) -> UIImage? {
        guard !uri.isEmpty,
              let data = uri.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Scale the 1-unit-per-module CIImage up to the requested point size.
        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
    #endif
}
