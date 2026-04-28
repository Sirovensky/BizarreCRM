#if canImport(UIKit)
import UIKit
import SwiftUI
import Core

// §17.4 Custom UIPrintPageRenderer for label printers (Dymo via AirPrint).
//
// AirPrint-connected label printers (Dymo LabelWriter, Brother QL-820NWBc) accept
// PDF via `UIPrintInteractionController`. However, for better control over per-label
// page sizing, we subclass `UIPrintPageRenderer` and render each label as a separate
// page with exact dimensions instead of scaling a multi-page PDF.
//
// Key advantage: Label printers need exact paper sizes (e.g. 2.125" × 1" for
// Dymo 30334). The `UIPrintPageRenderer` lets us control the printable rect per-page,
// which prevents the label printer from guessing and wasting stock.

// MARK: - LabelPageRenderer

/// Custom `UIPrintPageRenderer` that renders one `LabelView` per page at the
/// exact label stock dimensions. Pass this to `UIPrintInteractionController.printPageRenderer`.
public final class LabelPageRenderer: UIPrintPageRenderer {

    // MARK: - Types

    public struct LabelSpec: Sendable {
        /// Physical label size in inches. Used to compute point dimensions at the
        /// resolution reported by the print system (`UIPrintPageRenderer.currentRenderingQualityRequested`).
        public let widthInches: Double
        public let heightInches: Double

        /// Dymo 30334 medium address label (2.125" × 1.25")
        public static let dymo2125x125 = LabelSpec(widthInches: 2.125, heightInches: 1.25)
        /// Generic 2" × 1" thermal label (Zebra, Brother)
        public static let standard2x1 = LabelSpec(widthInches: 2.0, heightInches: 1.0)
        /// 4" × 6" shipping label
        public static let shipping4x6 = LabelSpec(widthInches: 4.0, heightInches: 6.0)
    }

    // MARK: - Properties

    private let payloads: [LabelPayload]
    private let spec: LabelSpec

    // MARK: - Init

    public init(payloads: [LabelPayload], spec: LabelSpec) {
        self.payloads = payloads
        self.spec = spec
        super.init()
    }

    // MARK: - UIPrintPageRenderer overrides

    override public var numberOfPages: Int {
        payloads.count
    }

    override public func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard pageIndex < payloads.count else { return }
        let payload = payloads[pageIndex]

        // Render SwiftUI LabelView into the current graphics context via UIGraphicsImageRenderer
        let medium: PrintMedium = .label2x4  // label2x4 covers all compact stock; contentWidth adapts
        let swiftUIView = LabelView(payload: payload)
            .environment(\.printMedium, medium)
        let renderer = UIGraphicsImageRenderer(size: printableRect.size)
        let image = renderer.image { _ in
            let vc = UIHostingController(rootView: swiftUIView)
            vc.view.frame = CGRect(origin: .zero, size: printableRect.size)
            vc.view.backgroundColor = .white
            vc.view.drawHierarchy(in: CGRect(origin: .zero, size: printableRect.size), afterScreenUpdates: true)
        }
        image.draw(in: printableRect)
    }

    // MARK: - Factory: printable rect per label

    public func paperRect(forPage pageIndex: Int) -> CGRect {
        let w = spec.widthInches * 72.0
        let h = spec.heightInches * 72.0
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

    public func printableRect(forPage pageIndex: Int) -> CGRect {
        return paperRect(forPage: pageIndex)
    }
}

// MARK: - LabelPrintInteractionCoordinator

/// Convenience wrapper: creates a `UIPrintInteractionController` configured
/// with a `LabelPageRenderer` and presents it from the given view controller.
@MainActor
public final class LabelPrintInteractionCoordinator {

    private let viewController: UIViewController

    public init(from viewController: UIViewController) {
        self.viewController = viewController
    }

    /// Print a batch of labels using the custom per-page renderer.
    /// - Parameters:
    ///   - payloads: One or more label payloads (one per label).
    ///   - spec: Physical label dimensions.
    public func printLabels(_ payloads: [LabelPayload], spec: LabelPageRenderer.LabelSpec) async {
        guard !payloads.isEmpty else { return }
        let renderer = LabelPageRenderer(payloads: payloads, spec: spec)
        let pic = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Labels (\(payloads.count))"
        pic.printInfo = printInfo
        pic.printPageRenderer = renderer

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pic.present(animated: true) { _, _, _ in
                continuation.resume()
            }
        }
    }
}
#endif
