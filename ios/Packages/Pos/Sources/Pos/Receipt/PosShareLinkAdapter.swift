#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Wraps `ShareLink(item:preview:)` for the system share sheet
/// (AirDrop, copy, third-party share targets) and `UIPrintInteractionController`
/// for Print.
///
/// Usage:
/// ```swift
/// PosShareLinkAdapter(receiptText: vm.receiptText, receiptHtml: vm.receiptHtml)
/// ```
///
/// The adapter is a thin `View` that presents either a `ShareLink` (for the
/// system sheet / AirDrop) or triggers `UIPrintInteractionController` for the
/// print channel. Both surfaces are exposed as SwiftUI-compatible views rather
/// than raw UIKit calls so the parent can compose them inline.
public struct PosShareLinkAdapter: View {
    public let receiptText: String
    public let invoiceLabel: String

    @State private var showPrintError: Bool = false

    public init(receiptText: String, invoiceLabel: String) {
        self.receiptText = receiptText
        self.invoiceLabel = invoiceLabel
    }

    public var body: some View {
        // System share sheet (AirDrop + all registered share extensions).
        ShareLink(
            item: receiptText,
            preview: SharePreview(
                "Receipt \(invoiceLabel)",
                icon: Image(systemName: "doc.text")
            )
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.brandLabelLarge())
        }
        .accessibilityLabel("Share receipt via AirDrop or other apps")
        .accessibilityHint("Opens the system share sheet")
    }
}

// MARK: - Print trigger view

/// A button that triggers `UIPrintInteractionController` for AirPrint. Exposed
/// separately so the receipt view can wire the Print tile independently.
public struct PosPrintButton: View {
    public let receiptText: String
    public let invoiceLabel: String

    public init(receiptText: String, invoiceLabel: String) {
        self.receiptText = receiptText
        self.invoiceLabel = invoiceLabel
    }

    public var body: some View {
        Button {
            printReceipt()
        } label: {
            Label("Print", systemImage: "printer")
                .font(.brandLabelLarge())
        }
        .accessibilityLabel("Print receipt")
        .accessibilityHint("Opens the AirPrint dialog")
    }

    private func printReceipt() {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Receipt \(invoiceLabel)"
        printInfo.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = receiptText as NSString

        controller.present(animated: true, completionHandler: { _, _, error in
            if let error {
                AppLog.pos.error("PosPrintButton: print failed — \(error.localizedDescription)")
            }
        })
    }
}
#endif
