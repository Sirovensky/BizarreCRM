import Foundation
#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit

// MARK: - ReceiptOCRService

/// Actor-isolated OCR service. Uses Apple Vision `VNRecognizeTextRequest`
/// (accurate mode) to extract text from a receipt image, then delegates
/// to `ReceiptParser` for structured extraction.
public actor ReceiptOCRService {

    // MARK: - Error

    public enum OCRError: Error, LocalizedError {
        case imageCGConversionFailed
        case noTextObservations
        case visionError(Error)

        public var errorDescription: String? {
            switch self {
            case .imageCGConversionFailed:
                return "Could not convert receipt image for processing."
            case .noTextObservations:
                return "No text was detected on the receipt."
            case .visionError(let e):
                return "Vision error: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Perform OCR on a UIImage and return structured receipt data.
    public func recognise(image: UIImage) async throws -> ReceiptOCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageCGConversionFailed
        }

        let rawText = try await performVisionOCR(on: cgImage)
        guard !rawText.isEmpty else {
            throw OCRError.noTextObservations
        }

        return ReceiptParser.parse(rawText: rawText)
    }

    // MARK: - Private

    private func performVisionOCR(on cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.visionError(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines: [String] = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.visionError(error))
            }
        }
    }
}

#endif
