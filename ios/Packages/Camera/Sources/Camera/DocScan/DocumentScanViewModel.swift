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

    // MARK: - Stored properties

    /// Ordered page images. Mutations drive SwiftUI updates automatically.
    public private(set) var pages: [UIImage] = []

    /// Current upload lifecycle state.
    public private(set) var uploadState: UploadState = .idle

    /// Injected uploader — takes PDF `Data`, returns the attachment URL.
    private let uploader: @Sendable (Data) async throws -> String

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
    public func generatePDF() -> Data? {
        guard !pages.isEmpty else { return nil }
        return assemblePDF(from: pages)
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
    }
}
#endif
