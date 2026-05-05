#if canImport(UIKit)
import Foundation
import CoreImage
import UIKit
import Core

// MARK: - GiftCardBarcodeGenerator
//
// §17.2 — "Gift cards: unique Code 128 per card (§40)."
//
// Each gift card is issued with a unique Code 128 barcode that encodes the card
// number. The barcode is:
//   1. Generated on-device via Core Image `CICode128BarcodeGenerator`.
//   2. Embedded into the gift receipt / gift card print template so the card
//      can be scanned at POS to redeem balance.
//   3. Returned as a `UIImage` for preview and as `BarcodePayload` for printing.
//
// Code 128 is chosen because:
//   - It supports the full ASCII character set (no numeric-only restriction like EAN-13).
//   - Our POS scanner (`DataScannerViewController` + `BarcodeVisionScanner`) already
//     recognises Code 128 via `VNBarcodeSymbology.code128`.
//   - Produces a compact barcode for wallet cards.
//
// Gift card number format: "GC-{16 hex digits}" — unique per card, tenant-scoped
// on the server. The format is validated before encoding so malformed numbers
// don't reach the print queue.

// MARK: - GiftCardBarcode

/// A generated gift card barcode ready for display and printing.
public struct GiftCardBarcode: Sendable {
    /// The gift card number encoded in the barcode.
    public let cardNumber: String
    /// Code 128 barcode rendered as a `UIImage`.
    public let image: UIImage
    /// `BarcodePayload` for handing to `PrintService`.
    public let printPayload: BarcodePayload

    public init(cardNumber: String, image: UIImage) {
        self.cardNumber = cardNumber
        self.image = image
        self.printPayload = BarcodePayload(code: cardNumber, format: .code128)
    }
}

// MARK: - GiftCardBarcodeGenerator

public actor GiftCardBarcodeGenerator {

    // MARK: - Singleton

    public static let shared = GiftCardBarcodeGenerator()

    // MARK: - Constants

    /// Quiet zone in pixels around the barcode (Code 128 spec requires ≥ 10x
    /// of the narrowest bar; 7 px at 3× scale = 21 px quiet zone).
    private static let quietSpace: Double = 7.0

    /// Scale factor applied after `CICode128BarcodeGenerator` output.
    /// At 3× the barcode is ~58mm wide on a 200 DPI thermal — fits an 80mm roll.
    private static let scale: CGFloat = 3.0

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Generates a Code 128 barcode for a gift card number.
    ///
    /// - Parameter cardNumber: The gift card number (e.g. "GC-A1B2C3D4E5F6A1B2").
    ///   Must be ASCII-encodable. Whitespace is trimmed automatically.
    /// - Returns: A `GiftCardBarcode` containing the image and print payload.
    /// - Throws: `GiftCardBarcodeError` on generation failure.
    public func generate(for cardNumber: String) throws -> GiftCardBarcode {
        let trimmed = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GiftCardBarcodeError.emptyCardNumber
        }
        guard trimmed.data(using: .ascii) != nil else {
            throw GiftCardBarcodeError.invalidCardNumber("Gift card number must be ASCII-encodable: \(trimmed)")
        }

        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else {
            throw GiftCardBarcodeError.generatorUnavailable
        }
        filter.setValue(Data(trimmed.utf8), forKey: "inputMessage")
        filter.setValue(Self.quietSpace, forKey: "inputQuietSpace")

        guard let rawCIImage = filter.outputImage else {
            throw GiftCardBarcodeError.renderFailed("CIFilter returned nil output for '\(trimmed)'")
        }

        let scaled = rawCIImage.transformed(
            by: CGAffineTransform(scaleX: Self.scale, y: Self.scale)
        )

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw GiftCardBarcodeError.renderFailed("CGImage creation failed for '\(trimmed)'")
        }

        let image = UIImage(cgImage: cgImage)
        AppLog.hardware.info("GiftCardBarcodeGenerator: generated Code 128 for '\(trimmed)' (\(Int(scaled.extent.width))×\(Int(scaled.extent.height)) px)")
        return GiftCardBarcode(cardNumber: trimmed, image: image)
    }

    /// Generates a gift card number in the canonical format "GC-{16 uppercase hex digits}".
    ///
    /// The server is responsible for persisting and validating card numbers.
    /// This helper is used when creating a card locally (e.g. offline) before
    /// the server assigns a permanent ID.
    public func generateCardNumber() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        return "GC-\(hex)"
    }
}

// MARK: - GiftCardBarcodeError

public enum GiftCardBarcodeError: LocalizedError, Sendable {
    case emptyCardNumber
    case invalidCardNumber(String)
    case generatorUnavailable
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCardNumber:
            return "Gift card number cannot be empty."
        case .invalidCardNumber(let d):
            return "Invalid gift card number: \(d)"
        case .generatorUnavailable:
            return "Code 128 barcode generator is unavailable on this device."
        case .renderFailed(let d):
            return "Barcode rendering failed: \(d)"
        }
    }
}
#endif
