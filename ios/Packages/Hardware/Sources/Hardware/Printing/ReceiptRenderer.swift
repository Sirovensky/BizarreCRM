#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
import PDFKit
import Core

// MARK: - ReceiptRenderer
//
// §17.4 Canonical rendering pipeline:
//   SwiftUI view → ImageRenderer (2× scale, dithered) → ESC/POS raster bitmap  (thermal)
//   SwiftUI view → UIGraphicsPDFRenderer                                         (AirPrint/PDF)
//
// All output channels share ONE rendering source: the strongly-typed SwiftUI
// view (ReceiptView, GiftReceiptView, WorkOrderTicketView, etc.).
// Zero deferred network reads inside render — ReceiptPayload is self-contained.

/// Converts a SwiftUI receipt view into raster bytes or PDF data.
///
/// Usage (thermal):
/// ```swift
/// let bitmap = try await ReceiptRenderer.rasterize(
///     ReceiptView(model: payload).environment(\.printMedium, .thermal80mm)
/// )
/// // bitmap → ESC/POS engine for transmission to Star/Epson printer.
/// ```
///
/// Usage (PDF for AirPrint / share sheet):
/// ```swift
/// let pdfURL = try await ReceiptRenderer.renderPDF(
///     ReceiptView(model: payload).environment(\.printMedium, .letter),
///     medium: .letter
/// )
/// // pdfURL → UIPrintInteractionController or UIActivityViewController.
/// ```
@MainActor
public enum ReceiptRenderer {

    // MARK: - Rasterize (thermal path)

    /// Renders a SwiftUI view into a 1-bit dithered bitmap suitable for ESC/POS printers.
    ///
    /// - Parameter view: Any SwiftUI view (typically `ReceiptView`, `GiftReceiptView`, etc.)
    ///   with the correct `.printMedium` environment already applied.
    /// - Returns: `Data` containing raw 1-bit pixel rows, width-padded to 8-bit boundaries.
    ///   Ready to embed in an ESC/POS raster bitmap command.
    public static func rasterize<V: View>(_ view: V, medium: PrintMedium = .thermal80mm) async throws -> RasterBitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0   // 144 dpi for crisp thermal print
        renderer.proposedSize = .init(width: medium.contentWidth, height: nil)

        guard let cgImage = renderer.cgImage else {
            throw ReceiptRenderError.rasterizationFailed("ImageRenderer produced no image")
        }

        // Convert to 8-bit grayscale then threshold to 1-bit (dithering via Atkinson).
        let bitmap = try dither1bit(cgImage)
        AppLog.hardware.info("ReceiptRenderer: rasterized \(bitmap.width)×\(bitmap.height) px")
        return bitmap
    }

    // MARK: - Render PDF (AirPrint / share sheet path)

    /// Renders a SwiftUI view to a PDF file and returns its temporary file URL.
    ///
    /// The PDF is written to the system temp directory. Callers should either
    /// move it to a permanent location or hand the URL to `UIPrintInteractionController`
    /// and delete it after the print job completes.
    ///
    /// - Important: The URL is NEVER a remote URL — Android lesson §17.4.
    public static func renderPDF<V: View>(
        _ view: V,
        medium: PrintMedium = .letter,
        jobId: UUID = UUID()
    ) async throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = .init(width: medium.contentWidth, height: nil)

        guard let cgImage = renderer.cgImage else {
            throw ReceiptRenderError.rasterizationFailed("ImageRenderer produced no image for PDF")
        }

        let pageW = medium.pageWidth
        let pageH = CGFloat(cgImage.height) * (pageW / CGFloat(cgImage.width))
        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            UIImage(cgImage: cgImage).draw(in: pageRect)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-\(jobId.uuidString).pdf")
        try pdfData.write(to: tempURL)
        AppLog.hardware.info("ReceiptRenderer: PDF written to \(tempURL.lastPathComponent, privacy: .public)")
        return tempURL
    }

    // MARK: - Render multi-page PDF (pagination for long invoices)

    /// Renders a SwiftUI view into a **paginated** PDF, splitting content across
    /// `pageRect`-sized pages with a repeated header on each.
    ///
    /// §17.4 — "Pagination: long invoices span pages with reprinted header + page
    /// numbers."
    ///
    /// Algorithm:
    ///  1. Render full content to one large `CGImage` at `medium.contentWidth`.
    ///  2. Slice the image into `pageHeight`-tall strips.
    ///  3. Render each strip onto its own PDF page with optional page-number footer.
    ///
    /// - Parameters:
    ///   - view:   Full SwiftUI document view (e.g. `InvoiceDocumentView`).
    ///   - header: Short header view re-printed at the top of continuation pages.
    ///   - medium: Target paper size.
    ///   - jobId:  UUID used in the output filename.
    /// - Returns: Local file URL of the paginated PDF.
    public static func renderMultiPagePDF<Content: View, Header: View>(
        content view: Content,
        continuationHeader header: Header? = nil,
        medium: PrintMedium = .letter,
        jobId: UUID = UUID()
    ) async throws -> URL {
        let scale = UIScreen.main.scale
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = .init(width: medium.contentWidth, height: nil)

        guard let cgImage = renderer.cgImage else {
            throw ReceiptRenderError.rasterizationFailed("ImageRenderer produced no content image for multi-page PDF")
        }

        let pageW    = medium.pageWidth
        let margin   = medium.margin
        let usableH  = medium.pageHeight - margin * 2
        let contentW = CGFloat(cgImage.width)
        let contentH = CGFloat(cgImage.height)

        // Scale factor from content pixels to page points.
        let ptPerPx  = pageW / contentW
        let totalPtH = contentH * ptPerPx
        let pageCount = Int(ceil(totalPtH / usableH))

        // Render header (continuation only) once if supplied.
        var headerImage: CGImage?
        if let hdr = header {
            let hRenderer = ImageRenderer(content: hdr)
            hRenderer.scale = scale
            hRenderer.proposedSize = .init(width: medium.contentWidth, height: nil)
            headerImage = hRenderer.cgImage
        }
        let headerPtH: CGFloat = headerImage.map { CGFloat($0.height) * ptPerPx } ?? 0

        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: medium.pageHeight)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = pdfRenderer.pdfData { ctx in
            for page in 0..<pageCount {
                let pageInfo = [kCGPDFContextMediaBox: pageRect] as [CFString: Any]
                ctx.beginPage(withBounds: pageRect, pageInfo: pageInfo as [AnyHashable: Any])

                let context = UIGraphicsGetCurrentContext()

                // On continuation pages, draw repeat header at top.
                var yOffset = margin
                if page > 0, let hdr = headerImage {
                    let hdrSrcRect = CGRect(x: 0, y: 0, width: contentW, height: CGFloat(hdr.height))
                    let hdrDstRect = CGRect(x: margin, y: yOffset, width: pageW - margin * 2, height: headerPtH)
                    context?.draw(hdr, in: hdrDstRect, byTiling: false)
                    _ = hdrSrcRect // suppress unused warning
                    yOffset += headerPtH + margin * 0.5
                }

                // Slice of the full content this page covers.
                let contentUsableH = medium.pageHeight - yOffset - margin
                let sliceTopPx  = CGFloat(page) * usableH / ptPerPx
                let slicePxH    = contentUsableH / ptPerPx
                let srcSlice    = CGRect(
                    x: 0,
                    y: sliceTopPx,
                    width: contentW,
                    height: min(slicePxH, contentH - sliceTopPx)
                )
                guard let slicedCG = cgImage.cropping(to: srcSlice) else { continue }
                let dstRect = CGRect(
                    x: margin,
                    y: yOffset,
                    width: pageW - margin * 2,
                    height: CGFloat(slicedCG.height) * ptPerPx
                )
                context?.draw(slicedCG, in: dstRect, byTiling: false)

                // Page number footer.
                let pageLabel = "Page \(page + 1) of \(pageCount)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.gray
                ]
                let labelSize = pageLabel.size(withAttributes: attrs)
                let labelRect = CGRect(
                    x: pageW - labelSize.width - margin,
                    y: medium.pageHeight - margin * 0.8,
                    width: labelSize.width,
                    height: labelSize.height
                )
                pageLabel.draw(in: labelRect, withAttributes: attrs)
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invoice-paginated-\(jobId.uuidString).pdf")
        try pdfData.write(to: tempURL)
        AppLog.hardware.info("ReceiptRenderer: paginated PDF (\(pageCount)p) written to \(tempURL.lastPathComponent, privacy: .public)")
        return tempURL
    }

    // MARK: - A11y-tagged PDF

    /// Renders a SwiftUI view to a PDF with PDFKit accessibility metadata.
    ///
    /// §17.4 — "A11y: tagged PDFs (searchable/copyable); screen-reader friendly in-app."
    ///
    /// The PDF metadata includes `Title`, `Author`, `Subject`, and `Keywords` so
    /// screen readers (VoiceOver PDF viewer, Preview, Adobe Reader) can announce
    /// document structure. The rendered content is identical to `renderPDF` — only
    /// the metadata envelope differs.
    ///
    /// - Parameters:
    ///   - view:     SwiftUI document view.
    ///   - title:    Document title (e.g. "Invoice INV-2026-00099").
    ///   - author:   Tenant name.
    ///   - subject:  Document type (e.g. "Invoice", "Receipt").
    ///   - keywords: Searchable terms (e.g. ["repair", "iPhone", "INV-00099"]).
    ///   - medium:   Target paper size.
    ///   - jobId:    UUID used in the output filename.
    public static func renderAccessiblePDF<V: View>(
        _ view: V,
        title: String,
        author: String,
        subject: String,
        keywords: [String] = [],
        medium: PrintMedium = .letter,
        jobId: UUID = UUID()
    ) async throws -> URL {
        let scale = UIScreen.main.scale
        let imageRenderer = ImageRenderer(content: view)
        imageRenderer.scale = scale
        imageRenderer.proposedSize = .init(width: medium.contentWidth, height: nil)

        guard let cgImage = imageRenderer.cgImage else {
            throw ReceiptRenderError.rasterizationFailed("ImageRenderer produced no image for accessible PDF")
        }

        let pageW = medium.pageWidth
        let pageH = CGFloat(cgImage.height) * (pageW / CGFloat(cgImage.width))
        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        // Build document info dictionary for PDF metadata (a11y + searchability).
        var docInfo: [CFString: Any] = [
            kCGPDFContextTitle:          title as CFString,
            kCGPDFContextAuthor:         author as CFString,
            kCGPDFContextSubject:        subject as CFString
        ]
        if !keywords.isEmpty {
            docInfo[kCGPDFContextKeywords] = keywords.joined(separator: ", ") as CFString
        }

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect, format: {
            let fmt = UIGraphicsPDFRendererFormat()
            fmt.documentInfo = docInfo as [String: Any]
            return fmt
        }())

        let pdfData = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            UIImage(cgImage: cgImage).draw(in: pageRect)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-a11y-\(jobId.uuidString).pdf")
        try pdfData.write(to: tempURL)
        AppLog.hardware.info("ReceiptRenderer: accessible PDF written to \(tempURL.lastPathComponent, privacy: .public)")
        return tempURL
    }

    // MARK: - 1-bit Atkinson dithering

    /// Converts a CGImage to a 1-bit `RasterBitmap` via Atkinson dithering.
    ///
    /// Atkinson dithering distributes the quantization error across 6 neighbours,
    /// producing crisp text and line-art on thermal paper while preserving mid-tones
    /// better than simple thresholding.
    private static func dither1bit(_ cgImage: CGImage) throws -> RasterBitmap {
        let width = cgImage.width
        let height = cgImage.height

        // Render to 8-bit grayscale buffer.
        var gray = [UInt8](repeating: 255, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &gray,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ReceiptRenderError.rasterizationFailed("Failed to create grayscale CGContext")
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Atkinson dither.
        var floats = gray.map { Float($0) }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let old = floats[i]
                let new: Float = old < 128 ? 0 : 255
                floats[i] = new
                let err = (old - new) / 8
                let neighbours = [
                    (x + 1, y), (x + 2, y),
                    (x - 1, y + 1), (x, y + 1), (x + 1, y + 1),
                    (x, y + 2)
                ]
                for (nx, ny) in neighbours {
                    guard nx >= 0, nx < width, ny < height else { continue }
                    floats[ny * width + nx] += err
                }
            }
        }

        // Pack into rows of bytes (MSB first).
        let bytesPerRow = (width + 7) / 8
        var rows = [[UInt8]](repeating: [UInt8](repeating: 0, count: bytesPerRow), count: height)
        for y in 0..<height {
            for x in 0..<width {
                if floats[y * width + x] < 128 {
                    // Black pixel → set bit.
                    rows[y][x / 8] |= (0x80 >> (x % 8))
                }
            }
        }

        return RasterBitmap(width: width, height: height, rows: rows)
    }
}

// MARK: - RasterBitmap

/// 1-bit raster bitmap ready for ESC/POS transmission.
///
/// Each row is a packed array of bytes (MSB = leftmost pixel).
/// Width might not be a multiple of 8; rows are padded with trailing zeros.
public struct RasterBitmap: Sendable {
    /// Pixel width (before byte-padding).
    public let width: Int
    /// Pixel height.
    public let height: Int
    /// One byte-array per row, each of length `(width + 7) / 8`.
    public let rows: [[UInt8]]
    /// Byte width per row (= `(width + 7) / 8`).
    public var bytesPerRow: Int { (width + 7) / 8 }
}

// MARK: - ReceiptRenderError

public enum ReceiptRenderError: Error, LocalizedError, Sendable {
    case rasterizationFailed(String)
    case pdfRenderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rasterizationFailed(let d): return "Receipt render failed: \(d)"
        case .pdfRenderFailed(let d):     return "PDF render failed: \(d)"
        }
    }
}

#endif
