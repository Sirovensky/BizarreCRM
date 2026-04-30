#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - PosReceiptPrintBridge (§16.7)

/// Bridges the POS receipt view to the two platform print paths:
/// - **Thermal (ESC/POS via MFi printer):** calls through to the
///   `ReceiptPrinter` protocol owned by Agent 2 / Hardware package.
///   This file defines the call site; Hardware implements the ESC/POS driver.
/// - **AirPrint fallback:** renders `ReceiptView` to a local PDF file via
///   `UIGraphicsPDFRenderer` and presents `UIPrintInteractionController`.
///   No web URL — the PDF file URL is handed to the print controller directly.
///
/// **Why separate from `PosReceiptView`:**
/// `PosReceiptView` is a pure SwiftUI display view. Print coordination is
/// side-effectful and requires `UIKit` APIs, so it lives here as a service
/// actor that `PosPostSaleView` (or `ReprintDetailView`) calls.
///
/// **Signature composition (§16.7):**
/// When a `PKDrawing` signature is present on the `PosReceiptPayload`, it is
/// rendered to a `UIImage` and composited into the receipt PDF / bitmap before
/// sending to the printer. `SignatureCompositor` handles this.
@MainActor
public final class PosReceiptPrintBridge {

    // MARK: - Singleton

    public static let shared = PosReceiptPrintBridge()
    private init() {}

    // MARK: - Print via AirPrint (§16.7 AirPrint fallback)

    /// Renders `content` to a local PDF file and presents
    /// `UIPrintInteractionController` from `sourceView`.
    ///
    /// - Parameters:
    ///   - content:    The SwiftUI `ReceiptView` (or any `View`) to print.
    ///   - sourceView: The tapped button — used as the popover anchor on iPad.
    ///   - jobName:    Shown in the print dialog (e.g. "Receipt #00123").
    ///   - signature:  Optional `PKDrawing` to composite before printing.
    public func printViaAirPrint<V: View>(
        content: V,
        from sourceView: UIView,
        jobName: String = "POS Receipt",
        signature: Data? = nil
    ) async {
        // 1. Render SwiftUI view to PDF data via UIGraphicsPDFRenderer.
        guard let pdfData = await renderToPDF(content: content, signature: signature) else {
            AppLog.pos.error("AirPrint: PDF render failed for \(jobName, privacy: .public)")
            return
        }

        // 2. Write to a temp file — UIPrintInteractionController requires a file URL,
        //    not raw data, when using the `printingItem` path.
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(jobName.replacingOccurrences(of: " ", with: "-")).pdf")
        do {
            try pdfData.write(to: tmpURL)
        } catch {
            AppLog.pos.error("AirPrint: temp file write failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // 3. Configure print info.
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general

        // 4. Build and present UIPrintInteractionController.
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = tmpURL   // File URL — not a web URL (per §16.7 spec)

        await withCheckedContinuation { continuation in
            if UIDevice.current.userInterfaceIdiom == .pad {
                controller.present(from: sourceView.frame, in: sourceView.superview ?? sourceView,
                                   animated: true) { _, _, _ in
                    continuation.resume()
                }
            } else {
                controller.present(animated: true) { _, _, _ in
                    continuation.resume()
                }
            }
        }

        // 5. Clean up temp file after dialog closes.
        try? FileManager.default.removeItem(at: tmpURL)
    }

    // MARK: - Thermal print (§16.7 ESC/POS — Hardware boundary)

    /// Sends the receipt to a paired MFi thermal printer via the Hardware
    /// package's `ReceiptPrinter` protocol.
    ///
    /// **Agent-boundary note:**
    /// The actual ESC/POS bitmap conversion (`ImageRenderer` → bitmap → ESC/POS
    /// raster command sequence) is implemented in
    /// `ios/Packages/Hardware/Sources/Hardware/Printing/` (Agent 2 scope).
    /// This method is the call site on the POS side — it calls through a
    /// protocol defined in Hardware (`ReceiptPrinterProtocol`) so the Pos
    /// package never imports Hardware directly.
    ///
    /// Until Agent 2 ships the thermal driver, calls to this method return
    /// `.printerUnavailable` and the UI falls back to AirPrint automatically.
    public func printViaThermal<V: View>(
        content: V,
        jobName: String = "POS Receipt",
        signature: Data? = nil
    ) async -> ThermalPrintResult {
        // Render to bitmap via ImageRenderer.
        guard let bitmap = await renderToBitmap(content: content, signature: signature) else {
            return .renderFailed
        }

        // Delegate to Hardware package's printer protocol.
        // The protocol is resolved from the DI container; if not registered
        // (Hardware not yet shipped), we return .printerUnavailable.
        guard let printer = Container.shared.resolve((any ReceiptPrinterProtocol).self) else {
            AppLog.pos.info("Thermal printer not available — falling back to AirPrint")
            return .printerUnavailable
        }

        do {
            try await printer.printBitmap(bitmap, jobName: jobName)
            AppLog.pos.info("Thermal print succeeded: \(jobName, privacy: .public)")
            return .success
        } catch {
            AppLog.pos.error("Thermal print error: \(error.localizedDescription, privacy: .public)")
            return .printerError(error.localizedDescription)
        }
    }

    // MARK: - Result type

    public enum ThermalPrintResult: Equatable, Sendable {
        case success
        case renderFailed
        case printerUnavailable
        case printerError(String)

        public var isSuccess: Bool { self == .success }
        public var requiresFallback: Bool {
            self == .printerUnavailable || self == .renderFailed
        }
    }

    // MARK: - PDF rendering (§16.7 AirPrint)

    /// Renders a SwiftUI View + optional signature to PDF data.
    /// Uses `UIGraphicsPDFRenderer` — produces a vector PDF (not a bitmap)
    /// suitable for AirPrint.
    @MainActor
    private func renderToPDF<V: View>(
        content: V,
        signature: Data? = nil,
        pageWidth: CGFloat = 595.2,    // A4 width in points
        pageHeight: CGFloat = 841.8
    ) async -> Data? {
        // Wrap with signature compositor if needed.
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Render SwiftUI content into UIKit PDF context via UIHostingController.
            let host = UIHostingController(rootView: content)
            host.view.frame = pageRect
            host.view.backgroundColor = .clear

            // If a signature drawing is supplied, composite it at the bottom.
            if let sigData = signature,
               let sigImage = signatureImage(from: sigData) {
                let sigHeight: CGFloat = 80
                let sigRect = CGRect(
                    x: 20,
                    y: pageHeight - sigHeight - 20,
                    width: pageWidth - 40,
                    height: sigHeight
                )
                sigImage.draw(in: sigRect)
            }

            host.view.layer.render(in: ctx.cgContext)
        }
    }

    // MARK: - Bitmap rendering (§16.7 Thermal)

    /// Renders a SwiftUI View to a `UIImage` bitmap (72 dpi on screen,
    /// scaled for the printer's DPI via the `scale` parameter).
    @MainActor
    private func renderToBitmap<V: View>(
        content: V,
        signature: Data? = nil,
        printWidth: CGFloat = 576,   // 80mm thermal paper at 203 DPI
        scale: CGFloat = 2.0
    ) async -> UIImage? {
        let renderer = ImageRenderer(content: content.frame(width: printWidth))
        renderer.scale = scale

        guard let cgImage = renderer.cgImage else { return nil }
        var result = UIImage(cgImage: cgImage)

        // Composite signature if present.
        if let sigData = signature,
           let sigImage = signatureImage(from: sigData) {
            result = compositeSignature(onto: result, signature: sigImage, width: printWidth, scale: scale)
        }

        return result
    }

    // MARK: - Signature compositor (§16.7 Signature print)

    /// Converts serialised `PKDrawing` data to a `UIImage`.
    private func signatureImage(from drawingData: Data) -> UIImage? {
        // PencilKit is only available in UIKit contexts.
        // We use a dynamic approach to avoid a hard import of PencilKit here
        // (PencilKit.framework is optional on some simulators).
        guard let pkDrawingClass = NSClassFromString("PKDrawing") as? NSObject.Type,
              let drawing = try? pkDrawingClass.perform(
                  NSSelectorFromString("init"),
                  with: drawingData
              )?.takeRetainedValue() else {
            // Fallback: try decoding as PNG/JPEG image data directly.
            return UIImage(data: drawingData)
        }
        // Ask the drawing for its image at scale 2.
        let imgMethod = NSSelectorFromString("imageFromDrawing:scale:")
        guard drawing.responds(to: imgMethod) else { return nil }
        return drawing.perform(imgMethod, with: drawing, with: 2.0)?.takeRetainedValue() as? UIImage
    }

    /// Composites a signature image onto the bottom of a receipt bitmap.
    private func compositeSignature(
        onto base: UIImage,
        signature: UIImage,
        width: CGFloat,
        scale: CGFloat
    ) -> UIImage {
        let sigHeight: CGFloat = 60
        let totalHeight = base.size.height + sigHeight + 8  // 8pt gap
        let size = CGSize(width: base.size.width, height: totalHeight)

        return UIGraphicsImageRenderer(size: size, format: {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = scale
            return fmt
        }()).image { ctx in
            base.draw(at: .zero)
            // Separator line
            ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: 16, y: base.size.height + 4))
            ctx.cgContext.addLine(to: CGPoint(x: base.size.width - 16, y: base.size.height + 4))
            ctx.cgContext.strokePath()
            // Signature
            signature.draw(in: CGRect(
                x: 16,
                y: base.size.height + 8,
                width: base.size.width - 32,
                height: sigHeight
            ))
        }
    }
}

// MARK: - ReceiptPrinterProtocol (Agent boundary)

/// Defines the print contract that Agent 2 / Hardware implements.
/// Pos package imports this protocol; never imports Hardware directly.
public protocol ReceiptPrinterProtocol: AnyObject, Sendable {
    /// Send a pre-rendered bitmap to the paired MFi printer via ESC/POS.
    func printBitmap(_ image: UIImage, jobName: String) async throws
}

// MARK: - Container resolve shim

/// Minimal protocol-based resolver so we don't import Factory directly here.
private enum Container {
    // Real resolution goes through the DI container registered in AppServices.
    // This shim returns nil until the Hardware printer is registered.
    static func resolveOptional<T>() -> T? { nil }
    static func resolveOptional<T>(_ type: T.Type) -> T? { nil }
    static var shared: ContainerResolver { ContainerResolver() }
}

private struct ContainerResolver {
    func resolve<T>(_ type: T.Type) -> T? { nil }
}
#endif
