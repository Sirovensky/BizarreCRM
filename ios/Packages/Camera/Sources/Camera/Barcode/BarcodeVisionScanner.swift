#if canImport(UIKit)
import Foundation
import Vision
import UIKit
import Core

// MARK: - BarcodeVisionScanner
//
// §17 — "Scanner via `VNBarcodeObservation`: recognize all formats concurrently"
//  - Support symbologies: EAN-13/EAN-8, UPC-A/UPC-E, Code 128, Code 39, Code 93,
//    ITF-14, DataMatrix, QR, Aztec, PDF417
//  - Priority per use-case: Inventory SKU Code 128 primary + QR secondary;
//    retail EAN-13/UPC-A auto-detect; IMEI/serial Code 128 or bare numeric.
//  - Checksum validation per symbology (EAN mod 10, ITF mod 10, etc.);
//    malformed → warning toast + no action.
//  - A11y: VoiceOver announces scanned code and matched item.
//
// This scanner complements `DataScannerViewController` (iOS 16+) by providing
// a frame-by-frame Vision path that works on older OS versions and in contexts
// where a full DataScannerViewController is inappropriate (e.g., a still image
// or a frame from AVCaptureSession that the app manages itself).

// MARK: - BarcodeVisionResult

/// A barcode detected by `VNDetectBarcodesRequest`.
public struct BarcodeVisionResult: Sendable, Equatable {
    /// Raw string payload decoded from the barcode.
    public let value: String
    /// VisionKit symbology (e.g. "EAN13", "QR").
    public let symbology: VNBarcodeSymbology
    /// Human-readable symbology name.
    public let symbologyName: String
    /// `true` if our checksum validator accepted this payload.
    public let checksumValid: Bool
    /// Bounding box in Vision normalized coordinates (origin bottom-left).
    public let boundingBox: CGRect

    public init(
        value: String,
        symbology: VNBarcodeSymbology,
        checksumValid: Bool,
        boundingBox: CGRect
    ) {
        self.value = value
        self.symbology = symbology
        self.symbologyName = symbology.humanReadableName
        self.checksumValid = checksumValid
        self.boundingBox = boundingBox
    }
}

// MARK: - BarcodeVisionScanner

/// Actor that wraps `VNDetectBarcodesRequest` for still-image and frame-based scanning.
///
/// Usage (still image):
/// ```swift
/// let scanner = BarcodeVisionScanner()
/// let results = try await scanner.scan(image: capturedImage)
/// ```
public actor BarcodeVisionScanner {

    // MARK: - Configuration

    /// All symbologies we want Vision to detect. The request runs concurrently
    /// across all enabled types per the Vision docs.
    public static let allSymbologies: [VNBarcodeSymbology] = [
        .ean13,
        .ean8,
        .upca,   // UPC-A (12-digit; distinct from EAN-13 in Vision framework)
        .upce,
        .code128,
        .code39,
        .code93,
        .itf14,
        .dataMatrix,
        .qr,
        .aztec,
        .pdf417,
    ]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Scan a `UIImage` for barcodes.
    ///
    /// - Parameter image: The image to scan.
    /// - Returns: Array of detected barcodes, possibly empty.
    ///   Invalid checksums are included but flagged via `checksumValid = false`.
    /// - Throws: `BarcodeVisionError` on request failure.
    public func scan(image: UIImage) async throws -> [BarcodeVisionResult] {
        guard let cgImage = image.cgImage else {
            throw BarcodeVisionError.invalidImage
        }
        return try await detectBarcodes(in: cgImage)
    }

    /// Scan a `CVPixelBuffer` (e.g. from AVCaptureSession) for barcodes.
    public func scan(pixelBuffer: CVPixelBuffer) async throws -> [BarcodeVisionResult] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        return try await perform(handler: handler)
    }

    // MARK: - Private: Vision request

    private func detectBarcodes(in cgImage: CGImage) async throws -> [BarcodeVisionResult] {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await perform(handler: handler)
    }

    private func perform(handler: VNImageRequestHandler) async throws -> [BarcodeVisionResult] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: BarcodeVisionError.detectionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let results = observations.compactMap { obs -> BarcodeVisionResult? in
                    guard let payload = obs.payloadStringValue, !payload.isEmpty else { return nil }
                    let valid = BarcodeChecksumValidator.validate(value: payload, symbology: obs.symbology)
                    return BarcodeVisionResult(
                        value: payload,
                        symbology: obs.symbology,
                        checksumValid: valid,
                        boundingBox: obs.boundingBox
                    )
                }
                continuation.resume(returning: results)
            }
            request.symbologies = Self.allSymbologies
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: BarcodeVisionError.detectionFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - BarcodeChecksumValidator

/// Per-symbology checksum validation.
///
/// References:
///  - EAN/UPC: Luhn-like mod-10 (same as IMEI checksum).
///  - ITF-14: mod-10 (same as EAN).
///  - Code 39 / 128 / QR / DataMatrix / Aztec / PDF417 / Code 93:
///    checksums are embedded in the symbology and validated by the hardware scanner
///    or VisionKit; we pass these through as valid.
public enum BarcodeChecksumValidator {

    /// Returns `true` if the barcode value passes the expected checksum for its symbology.
    public static func validate(value: String, symbology: VNBarcodeSymbology) -> Bool {
        switch symbology {
        case .ean13:
            return validateEAN(value, expectedLength: 13)
        case .ean8:
            return validateEAN(value, expectedLength: 8)
        case .upca:
            // UPC-A is a 12-digit code; same mod-10 GS1 algorithm as EAN-13.
            return validateEAN(value, expectedLength: 12)
        case .upce:
            // UPC-E is typically 6–8 digits; checksum validation requires expansion to UPC-A first.
            // VisionKit delivers the 6-digit zero-suppressed form; we accept it if digit-only.
            return value.allSatisfy(\.isNumber) && (6...8).contains(value.count)
        case .itf14:
            return validateEAN(value, expectedLength: 14)
        default:
            // Code 128, Code 39, QR, DataMatrix, Aztec, PDF417, Code 93 — checksums
            // are handled by Vision internals; returned observations already passed.
            return true
        }
    }

    // MARK: - EAN / ITF mod-10 checksum (GS1 spec)

    /// Validates an EAN / ITF-14 barcode via the standard mod-10 GS1 algorithm.
    ///
    /// - Parameter value: The full barcode string including the check digit.
    /// - Parameter expectedLength: Expected character count (8, 13, or 14).
    static func validateEAN(_ value: String, expectedLength: Int) -> Bool {
        let digits = value.compactMap { $0.wholeNumberValue }
        guard digits.count == expectedLength else { return false }

        // GS1 mod-10: multiply alternating digits by 3 or 1 (starting from right, second from last).
        // EAN-13 / ITF-14 weights right-to-left: 1, 3, 1, 3, …
        // EAN-8 same pattern.
        var sum = 0
        for (index, digit) in digits.dropLast().reversed().enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        let computedCheck = (10 - (sum % 10)) % 10
        return computedCheck == digits.last
    }
}

// MARK: - BarcodeVisionError

public enum BarcodeVisionError: Error, LocalizedError, Sendable {
    case invalidImage
    case detectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image could not be processed for barcode detection."
        case .detectionFailed(let detail):
            return "Barcode detection failed: \(detail)"
        }
    }
}

// MARK: - VNBarcodeSymbology helpers

extension VNBarcodeSymbology {
    /// Human-readable name for display and accessibility announcements.
    public var humanReadableName: String {
        switch self {
        case .ean13:      return "EAN-13"
        case .ean8:       return "EAN-8"
        case .upca:       return "UPC-A"
        case .upce:       return "UPC-E"
        case .code128:    return "Code 128"
        case .code39:     return "Code 39"
        case .code93:     return "Code 93"
        case .itf14:      return "ITF-14"
        case .dataMatrix: return "DataMatrix"
        case .qr:         return "QR Code"
        case .aztec:      return "Aztec"
        case .pdf417:     return "PDF417"
        default:          return rawValue
        }
    }

    /// Priority description for use-case mapping per §17.
    public var useCasePriority: String {
        switch self {
        case .code128:    return "Inventory SKU (primary)"
        case .qr:         return "Inventory SKU (secondary) / Ticket link"
        case .ean13, .ean8, .upca: return "Retail barcode"
        case .upce:       return "Retail barcode (compact)"
        case .itf14:      return "Shipping / carton"
        case .dataMatrix, .aztec, .pdf417: return "Document / 2D"
        case .code39, .code93: return "Legacy / IMEI"
        default:          return "Other"
        }
    }
}

// MARK: - VoiceOver announcement helper

/// Generates an accessibility announcement string for a scanned barcode.
///
/// Usage:
/// ```swift
/// UIAccessibility.post(notification: .announcement,
///     argument: BarcodeA11yAnnouncer.announcement(for: result, itemName: "iPhone 13 Case"))
/// ```
public enum BarcodeA11yAnnouncer {

    public static func announcement(for result: BarcodeVisionResult, itemName: String?) -> String {
        var parts: [String] = []
        parts.append("\(result.symbologyName) scanned")
        if let name = itemName {
            parts.append("matched item: \(name)")
        } else {
            parts.append("value: \(result.value)")
        }
        if !result.checksumValid {
            parts.append("checksum invalid — verify the barcode")
        }
        return parts.joined(separator: ". ")
    }
}

#endif
