#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import UIKit
import VisionKit
import PDFKit
import Core

// MARK: - ScanResult

/// Immutable result delivered by ``DocumentScanner`` after a successful scan.
/// `pages` contains the corrected UIImages in order; `pdfData` is a
/// single-file PDF assembled via PDFKit (one page per image).
/// Both fields are captured at scan time — the caller is free to discard
/// the sheet immediately without losing data.
public struct ScanResult: Sendable {
    /// Ordered page images, perspective-corrected by VisionKit.
    public let pages: [UIImage]
    /// PDF assembled from `pages` via PDFKit. Ready for upload.
    public let pdfData: Data

    public init(pages: [UIImage], pdfData: Data) {
        self.pages = pages
        self.pdfData = pdfData
    }
}

// MARK: - PDF Assembly

/// Assembles an ordered array of `UIImage` values into a single-file PDF.
/// Each image occupies one A4-sized page (595 × 842 pt). The image is drawn
/// full-bleed, preserving aspect ratio with letterboxing if the aspect differs.
///
/// Exposed as a `public func` so `DocumentScanViewModel` and tests can call
/// it without going through the full UIViewControllerRepresentable machinery.
public func assemblePDF(from images: [UIImage]) -> Data {
    let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi pt
    let pdfDoc = PDFDocument()
    for (index, image) in images.enumerated() {
        guard let cgImage = image.cgImage else { continue }
        let pdfPage = PDFPage(image: image) ?? makePDFPage(cgImage: cgImage, rect: pageRect)
        pdfDoc.insert(pdfPage, at: index)
    }
    return pdfDoc.dataRepresentation() ?? Data()
}

private func makePDFPage(cgImage: CGImage, rect: CGRect) -> PDFPage {
    // Fallback: render into a UIGraphicsPDFRenderer and wrap.
    let renderer = UIGraphicsPDFRenderer(bounds: rect)
    let data = renderer.pdfData { ctx in
        ctx.beginPage()
        let imgRect = aspectFit(CGSize(width: cgImage.width, height: cgImage.height), into: rect)
        UIImage(cgImage: cgImage).draw(in: imgRect)
    }
    // Load the single-page PDF data back as a PDFPage.
    if let doc = PDFDocument(data: data), let page = doc.page(at: 0) {
        return page
    }
    // Last-resort empty page (should never happen).
    return PDFPage()
}

private func aspectFit(_ size: CGSize, into bounds: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return bounds }
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let w = size.width * scale
    let h = size.height * scale
    return CGRect(
        x: bounds.midX - w / 2,
        y: bounds.midY - h / 2,
        width: w,
        height: h
    )
}

// MARK: - DocumentScanner

/// `UIViewControllerRepresentable` wrapping `VNDocumentCameraViewController`.
///
/// Present this as a full-screen sheet. When the user finishes scanning,
/// `onFinished` is called with a ``ScanResult`` containing ordered page
/// images and a ready-to-upload PDF blob. Cancel and error callbacks fire
/// instead when the user dismisses without scanning or a hardware error
/// occurs.
///
/// Usage:
/// ```swift
/// .fullScreenCover(isPresented: $showScanner) {
///     DocumentScanner(
///         onFinished: { result in attachPages(result) },
///         onCanceled: { showScanner = false },
///         onError:    { err in handleError(err) }
///     )
/// }
/// ```
public struct DocumentScanner: UIViewControllerRepresentable {
    public let onFinished: @Sendable (ScanResult) -> Void
    public let onCanceled: @Sendable () -> Void
    public let onError:    @Sendable (Error) -> Void

    public init(
        onFinished: @escaping @Sendable (ScanResult) -> Void,
        onCanceled: @escaping @Sendable () -> Void,
        onError:    @escaping @Sendable (Error) -> Void
    ) {
        self.onFinished = onFinished
        self.onCanceled = onCanceled
        self.onError    = onError
    }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished, onCanceled: onCanceled, onError: onError)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate, @unchecked Sendable {
        private let onFinished: @Sendable (ScanResult) -> Void
        private let onCanceled: @Sendable () -> Void
        private let onError:    @Sendable (Error) -> Void

        init(
            onFinished: @escaping @Sendable (ScanResult) -> Void,
            onCanceled: @escaping @Sendable () -> Void,
            onError:    @escaping @Sendable (Error) -> Void
        ) {
            self.onFinished = onFinished
            self.onCanceled = onCanceled
            self.onError    = onError
        }

        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            let pdf = assemblePDF(from: pages)
            let result = ScanResult(pages: pages, pdfData: pdf)
            onFinished(result)
        }

        public func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCanceled()
        }

        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onError(error)
        }
    }
}
#endif
