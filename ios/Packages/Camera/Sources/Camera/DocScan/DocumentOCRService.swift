#if canImport(UIKit)
import Foundation
import Vision
import UIKit
import Core

// MARK: - DocumentOCRService
//
// §ActionPlan DocScan — "OCR via VNRecognizeTextRequest, text searchable via FTS5"
// Privacy: on-device Vision only; no external/cloud OCR.
//
// Returns the full extracted text from a set of scanned page images.
// The caller is responsible for indexing `ocrText` into FTS5 (via the Search
// package's FTS indexer) — this actor only performs the Vision extraction.

/// On-device document OCR using Apple Vision framework.
///
/// Usage:
/// ```swift
/// let service = DocumentOCRService()
/// let result = try await service.extractText(from: pages)
/// // result.fullText — searchable plain text
/// // result.pageTexts — per-page text array
/// ```
///
/// All processing is on-device. No data is sent to external services.
public actor DocumentOCRService {

    // MARK: - Result

    /// Extracted text from one or more scanned pages.
    public struct OCRResult: Sendable {
        /// Concatenated text from all pages, separated by page breaks.
        public let fullText: String
        /// Per-page text strings in the same order as the input images.
        public let pageTexts: [String]
        /// Number of pages processed.
        public let pageCount: Int

        public var isEmpty: Bool { fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Extract text from an ordered array of scanned page images.
    ///
    /// - Parameter pages: Page images from `VNDocumentCameraScan.imageOfPage(at:)`.
    /// - Returns: `OCRResult` with per-page and combined text.
    /// - Throws: `DocumentOCRError.recognitionFailed` if Vision cannot process an image.
    public func extractText(from pages: [UIImage]) async throws -> OCRResult {
        guard !pages.isEmpty else {
            return OCRResult(fullText: "", pageTexts: [], pageCount: 0)
        }

        var pageTexts: [String] = []
        for image in pages {
            let text = try await recognizePage(image)
            pageTexts.append(text)
        }

        let full = pageTexts.joined(separator: "\n\n---\n\n")
        AppLog.camera.info("DocumentOCRService: extracted \(full.count) chars from \(pages.count) page(s)")
        return OCRResult(fullText: full, pageTexts: pageTexts, pageCount: pages.count)
    }

    /// Extract text from a single page image.
    ///
    /// - Parameter image: A scanned page `UIImage`.
    /// - Returns: Recognized text string (may be empty if no text found).
    public func extractText(fromPage image: UIImage) async throws -> String {
        try await recognizePage(image)
    }

    // MARK: - Private: Vision recognition

    private func recognizePage(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw DocumentOCRError.invalidImage("UIImage has no CGImage backing")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: DocumentOCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            // §ActionPlan: accurate mode for high-quality OCR; on-device only.
            request.recognitionLevel = .accurate
            // Disable server-side processing — privacy requirement.
            // recognitionLanguages defaults to the device locale; covers most use cases.
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: DocumentOCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - DocumentOCRError

public enum DocumentOCRError: Error, LocalizedError, Sendable {
    case invalidImage(String)
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage(let detail):
            return "Invalid image for OCR: \(detail)"
        case .recognitionFailed(let detail):
            return "Text recognition failed: \(detail)"
        }
    }
}

#endif
