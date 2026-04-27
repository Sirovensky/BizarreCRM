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
