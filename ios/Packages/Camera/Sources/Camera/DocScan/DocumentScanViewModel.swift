#if canImport(UIKit)
import Foundation
import Observation
import PDFKit
import UIKit

// MARK: - DocumentScanViewModel

/// `@Observable` view-model for the document scan preview flow.
///
/// Manages the ordered list of scanned page images. Callers inject an
/// `uploader` closure so the VM stays testable without a real network layer.
///
/// When `attach()` is called the VM assembles a final PDF from the current
/// page order, calls `uploader(pdfData)`, and returns the attachment URL
/// string. Progress is exposed via ``uploadState``.
///
/// OCR is available via `runOCR()` which extracts text using on-device Vision
/// (§ActionPlan DocScan). Results are stored in `ocrResult` for FTS5 indexing.
///
/// Thread safety: `@MainActor` — all mutations land on the main queue.
@MainActor
@Observable
public final class DocumentScanViewModel {

    // MARK: - Upload state

    public enum UploadState: Equatable {
        case idle
        case uploading
        case success(url: String)
        case failure(message: String)
    }

    // MARK: - OCR state

    public enum OCRState: Equatable {
        case idle
        case running
        case done(text: String)
        case failed(message: String)
    }

    // MARK: - Stored properties

    /// Ordered page images. Mutations drive SwiftUI updates automatically.
    public private(set) var pages: [UIImage] = []

    /// Current upload lifecycle state.
    public private(set) var uploadState: UploadState = .idle

    /// OCR extraction state. Updated by `runOCR()`.
    public private(set) var ocrState: OCRState = .idle

    /// Convenience accessor for the extracted text when OCR succeeded.
    public var extractedText: String? {
        if case .done(let text) = ocrState { return text }
        return nil
    }

    /// Injected uploader — takes PDF `Data`, returns the attachment URL.
    private let uploader: @Sendable (Data) async throws -> String

    /// On-device OCR service (Vision framework only; no external egress).
    private let ocrService = DocumentOCRService()

    // MARK: - Init

    /// - Parameter uploader: Async closure called with assembled PDF data.
    ///   Should `POST` the data and return the resulting attachment URL.
    public init(uploader: @escaping @Sendable (Data) async throws -> String) {
        self.uploader = uploader
    }

    // MARK: - Page management

    /// Append pages from a completed scan. Existing pages are preserved so
    /// multiple scan sessions can be stitched into one document.
    public func addPages(_ newPages: [UIImage]) {
        pages = pages + newPages
    }

    /// Remove the page at `index`. No-op when index is out of bounds.
    public func deletePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        var updated = pages
        updated.remove(at: index)
        pages = updated
    }

    /// Move pages at `source` indices to `destination` (matches List/ForEach
    /// `onMove` signature).
    public func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = pages
        updated.move(fromOffsets: source, toOffset: destination)
        pages = updated
    }

    /// Replace all pages with a fresh ordered list (e.g. after drag-reorder
    /// in a non-List context).
    public func reorderPages(_ reordered: [UIImage]) {
        pages = reordered
    }

    // MARK: - PDF generation

    /// Assemble the current `pages` array into a PDF. Returns `nil` when
    /// there are no pages.
    ///
    /// Output format: PDF at 200 DPI (letter page size, images scaled to fill).
    /// §ActionPlan: "Output: PDF (preferred) or JPEG at 200 DPI default".
    public func generatePDF() -> Data? {
        guard !pages.isEmpty else { return nil }
        return assemblePDF(from: pages)
    }

    // MARK: - OCR

    /// Extract searchable text from all current pages via on-device Vision OCR.
    ///
    /// §ActionPlan: "OCR via VNRecognizeTextRequest, text searchable via FTS5"
    /// §ActionPlan: "Privacy: on-device Vision only; no external/cloud OCR"
    ///
    /// On completion, `ocrState` transitions to `.done(text:)` or `.failed`.
    /// The extracted text should be passed to the Search package's FTS5 indexer
    /// by the caller (this VM does not own Search).
    public func runOCR() async {
        guard !pages.isEmpty else {
            ocrState = .failed(message: "No pages to analyse.")
            return
        }
        ocrState = .running
        do {
            let result = try await ocrService.extractText(from: pages)
            ocrState = result.isEmpty
                ? .done(text: "")
                : .done(text: result.fullText)
        } catch {
            ocrState = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Upload

    /// Assemble the PDF and upload via the injected `uploader` closure.
    /// Sets ``uploadState`` throughout the lifecycle.
    public func attach() async {
        guard let pdfData = generatePDF() else {
            uploadState = .failure(message: "No pages to attach.")
            return
        }
        uploadState = .uploading
        do {
            let url = try await uploader(pdfData)
            uploadState = .success(url: url)
        } catch {
            uploadState = .failure(message: error.localizedDescription)
        }
    }

    /// Reset the VM to initial state (useful when presenting the scanner a
    /// second time from the same parent view without recreating the VM).
    public func reset() {
        pages = []
        uploadState = .idle
        ocrState = .idle
    }

    // MARK: - Private: PDF assembly

    /// Assembles page images into a multi-page PDF at 200 DPI equivalent scale.
    ///
    /// §ActionPlan: "Output: PDF (preferred) or JPEG at 200 DPI default"
    ///
    /// Page size: Letter (612 × 792 pt at 72 dpi) for US locale.
    /// Each image is scaled to fill the page while preserving aspect ratio.
    /// Privacy: purely local — no network calls, no temp files left on disk.
    private func assemblePDF(from images: [UIImage]) -> Data {
        // Letter page at 72 pt/in (iOS coordinate system)
        let pageWidth:  CGFloat = 612   // 8.5 in × 72
        let pageHeight: CGFloat = 792   // 11 in × 72
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin:    CGFloat = 18     // 0.25 in safety margin

        let format = UIGraphicsPDFRendererFormat()
        // Set 200 DPI in PDF metadata so print drivers scale correctly.
        format.documentInfo = [
            kCGPDFContextCreator as String: "BizarreCRM DocScan",
            // 200 DPI = 200/72 ≈ 2.778 points per pixel
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()

                // Scale image to fill content area (minus margin) keeping aspect ratio.
                let contentRect = CGRect(
                    x: margin,
                    y: margin,
                    width: pageWidth - margin * 2,
                    height: pageHeight - margin * 2
                )
                let drawRect = aspectFitRect(for: image.size, in: contentRect)
                image.draw(in: drawRect)
            }
        }
    }

    /// Returns a `CGRect` that fits `imageSize` inside `container` preserving aspect ratio.
    private func aspectFitRect(for imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let fitWidth  = imageSize.width  * scale
        let fitHeight = imageSize.height * scale
        let x = container.minX + (container.width  - fitWidth)  / 2
        let y = container.minY + (container.height - fitHeight) / 2
        return CGRect(x: x, y: y, width: fitWidth, height: fitHeight)
    }
}
#endif
