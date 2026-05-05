#if canImport(UIKit)
import UIKit
import Vision
import Core

/// Vision-based utilities for expense-receipt processing.
///
/// - ``detectQuadrilateral(_:)`` — finds the dominant rectangular region in a
///   photo using `VNDetectRectanglesRequest` so the caller can crop / perspective-
///   correct the receipt before upload.
///
/// - ``ocrTotal(_:)`` — extracts a probable total amount from receipt text via
///   `VNRecognizeTextRequest`, enabling expense pre-fill in the UI.
public struct ReceiptEdgeDetector {

    private init() {}

    // MARK: - Rectangle detection

    /// Detects the most prominent quadrilateral (receipt outline) in `image`.
    ///
    /// Returns a `CGRect` in **UIKit coordinates** (origin top-left, size in
    /// points) representing the bounding box of the detected rectangle.
    /// Returns `nil` if no rectangle is found or Vision fails.
    public static func detectQuadrilateral(_ image: UIImage) async -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRectangleObservation],
                      let best = results.max(by: { $0.confidence < $1.confidence }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let rect = vnRectToUIKit(best.boundingBox, imageSize: image.size)
                continuation.resume(returning: rect)
            }
            request.minimumAspectRatio = 0.5
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.2
            request.minimumConfidence = 0.5
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLog.ui.error("ReceiptEdgeDetector Vision failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - OCR total extraction

    /// Scans receipt text for a monetary total using `VNRecognizeTextRequest`.
    ///
    /// Heuristic: finds the last line that looks like a currency amount
    /// (e.g. `$12.50`, `12.50`, `USD 12.50`). This matches most receipt layouts
    /// where the total appears at the bottom.
    ///
    /// Returns `nil` if no amount is recognised.
    public static func ocrTotal(_ image: UIImage) async -> Double? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Gather all lines, sorted by vertical position (bottom → top).
                let lines: [String] = observations
                    .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }

                // Walk from the bottom; return the first parseable monetary value.
                for line in lines.reversed() {
                    if let amount = parseCurrencyAmount(from: line) {
                        continuation.resume(returning: amount)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLog.ui.error("ReceiptEdgeDetector OCR failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Helpers

    /// Converts a normalised VN bounding box (origin bottom-left, [0,1]) to
    /// UIKit coordinates (origin top-left, points).
    private static func vnRectToUIKit(_ normalised: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalised.origin.x * imageSize.width
        let y = (1.0 - normalised.origin.y - normalised.height) * imageSize.height
        let w = normalised.width * imageSize.width
        let h = normalised.height * imageSize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Parses a monetary amount from a receipt line string.
    /// Handles formats: `$12.50`, `12.50`, `12,50`, `USD12.50`, `TOTAL 12.50`.
    private static func parseCurrencyAmount(from text: String) -> Double? {
        // Match an optional currency symbol/code then digits with decimal separator.
        let pattern = #"(?:[$€£¥]|USD|EUR|GBP|CAD|AUD)?\s*(\d{1,6}[.,]\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        let captured = nsText.substring(with: captureRange)
            .replacingOccurrences(of: ",", with: ".")
        return Double(captured)
    }
}
#endif
