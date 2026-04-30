#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Core
import DesignSystem
import Networking

// MARK: - §6.1 / §6.8 Inventory Mass Label Print
//
// Renders a multi-page PDF — one label per selected item — and presents
// UIPrintInteractionController (AirPrint). MFi path deferred to Agent 2.
//
// Label content per item:
//   • Item name (bold)
//   • SKU (monospaced) + Code-128 barcode image
//   • Retail price
//   • Format picker: Small (2"×1") / Medium (2"×2")

// MARK: - Label Format

public enum InventoryLabelFormat: String, CaseIterable, Identifiable, Sendable {
    case small = "Small (2\"×1\")"
    case medium = "Medium (2\"×2\")"

    public var id: String { rawValue }

    var pointSize: CGSize {
        switch self {
        case .small:  return CGSize(width: 144, height: 72)   // 2" × 1" @ 72ppi
        case .medium: return CGSize(width: 144, height: 144)  // 2" × 2" @ 72ppi
        }
    }
}

// MARK: - Sheet View

/// Presents label format picker + preview thumbnail, then launches AirPrint.
public struct InventoryLabelPrintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [InventoryListItem]
    @State private var format: InventoryLabelFormat = .small
    @State private var isPrinting: Bool = false
    @State private var printError: String?
    @State private var previewImage: UIImage?

    public init(items: [InventoryListItem]) {
        self.items = items
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if items.isEmpty {
                    emptyState
                } else {
                    Form {
                        Section("Label format") {
                            Picker("Format", selection: $format) {
                                ForEach(InventoryLabelFormat.allCases) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }

                        Section("Preview (\(items.count) label\(items.count == 1 ? "" : "s"))") {
                            if let img = previewImage {
                                HStack {
                                    Spacer()
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 120)
                                        .border(Color.bizarreOnSurfaceMuted, width: 0.5)
                                    Spacer()
                                }
                            } else {
                                ProgressView("Rendering…")
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if let err = printError {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.bizarreError)
                                    Text(err)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreError)
                                }
                            }
                        }

                        Section {
                            Button {
                                Task { await printLabels() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isPrinting {
                                        ProgressView()
                                    } else {
                                        Label("Print with AirPrint", systemImage: "printer")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(isPrinting)
                            .accessibilityLabel("Print labels using AirPrint")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Print Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: format) {
                await renderPreview()
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Render preview

    private func renderPreview() async {
        guard let first = items.first else { return }
        let fmt = format
        previewImage = await Task.detached(priority: .userInitiated) {
            InventoryLabelRenderer.renderPreviewImage(item: first, format: fmt)
        }.value
    }

    // MARK: - AirPrint

    @MainActor
    private func printLabels() async {
        isPrinting = true
        printError = nil
        defer { isPrinting = false }

        let itemsCopy = items
        let fmt = format
        let pdfData = await Task.detached(priority: .userInitiated) {
            InventoryLabelRenderer.renderPDF(items: itemsCopy, format: fmt)
        }.value

        guard let pdfData else {
            printError = "Failed to render labels."
            return
        }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Inventory Labels"
        printInfo.outputType = .photo    // produces best quality on thermal printers via AirPrint

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfData

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            printError = "Cannot present print dialog."
            return
        }

        let printErrorMsg: String? = await withCheckedContinuation { continuation in
            controller.present(animated: true) { _, _, error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
        if let printErrorMsg {
            printError = printErrorMsg
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "printer.dotmatrix")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No items to print")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Select items in the inventory list first.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Label Renderer

/// Pure renderer: builds PDF pages from InventoryListItem data.
/// Each page = one label at the chosen physical size.
/// `enum` (no stored state) is implicitly `Sendable`.
enum InventoryLabelRenderer: Sendable {

    static func renderPDF(items: [InventoryListItem], format: InventoryLabelFormat) -> Data? {
        let size = format.pointSize
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for item in items {
                ctx.beginPage()
                drawLabel(item: item, in: CGRect(origin: .zero, size: size), format: format)
            }
        }
    }

    static func renderPreviewImage(item: InventoryListItem, format: InventoryLabelFormat) -> UIImage {
        let scale: CGFloat = 2.0
        let size = format.pointSize
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawLabel(item: item, in: CGRect(origin: .zero, size: size), format: format)
        }
    }

    // MARK: Label drawing

    private static func drawLabel(item: InventoryListItem, in rect: CGRect, format: InventoryLabelFormat) {
        let padding: CGFloat = 4
        let inner = rect.insetBy(dx: padding, dy: padding)

        // Name
        let nameFont = UIFont.systemFont(ofSize: format == .small ? 8 : 10, weight: .bold)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: UIColor.black
        ]
        let name = item.displayName as NSString
        let nameRect = CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.65, height: nameFont.lineHeight * 2)
        name.draw(in: nameRect, withAttributes: nameAttrs)

        // SKU
        let skuFont = UIFont.monospacedSystemFont(ofSize: format == .small ? 7 : 9, weight: .regular)
        let skuAttrs: [NSAttributedString.Key: Any] = [
            .font: skuFont,
            .foregroundColor: UIColor.darkGray
        ]
        let skuText = "SKU \(item.sku ?? String(item.id))" as NSString
        let skuY = nameRect.maxY + 2
        skuText.draw(at: CGPoint(x: inner.minX, y: skuY), withAttributes: skuAttrs)

        // Price
        if let cents = item.priceCents {
            let priceFont = UIFont.systemFont(ofSize: format == .small ? 7 : 9, weight: .medium)
            let price = String(format: "$%.2f", Double(cents) / 100.0) as NSString
            let priceAttrs: [NSAttributedString.Key: Any] = [.font: priceFont, .foregroundColor: UIColor.black]
            price.draw(at: CGPoint(x: inner.minX, y: skuY + skuFont.lineHeight + 2), withAttributes: priceAttrs)
        }

        // Barcode (Code-128 via CoreImage)
        let barcodeCode = item.sku ?? String(item.id)
        if let barcodeImage = generateCode128(code: barcodeCode) {
            let barcodeW = inner.width * 0.32
            let barcodeH = format == .small ? inner.height * 0.7 : inner.height * 0.5
            let barcodeRect = CGRect(
                x: inner.maxX - barcodeW,
                y: inner.minY,
                width: barcodeW,
                height: barcodeH
            )
            barcodeImage.draw(in: barcodeRect)
        }
    }

    // MARK: Code-128 barcode via CoreImage

    private static func generateCode128(code: String) -> UIImage? {
        guard let data = code.data(using: .ascii) else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = data
        filter.quietSpace = 2
        guard let output = filter.outputImage else { return nil }
        // Scale up for crisp rendering at label size
        let scale = CGAffineTransform(scaleX: 2, y: 2)
        let scaled = output.transformed(by: scale)
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
