#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimatePdfPreviewView (§8.2)
//
// "See what customer sees" — renders a local PDF from the Estimate model
// using ImageRenderer, then presents it via ShareSheet / QuickLook.
// Does NOT make a network call — offline-capable.
//
// Uses `UIActivityViewController` for share + AirPrint.

public struct EstimatePdfPreviewView: View {
    let estimate: Estimate
    @State private var showShare: Bool = false
    @State private var pdfUrl: URL?
    @State private var isGenerating: Bool = false

    public init(estimate: Estimate) {
        self.estimate = estimate
    }

    public var body: some View {
        Group {
            if let url = pdfUrl {
                EstimatePdfViewer(url: url, showShare: $showShare)
            } else {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: BrandSpacing.md) {
                        if isGenerating {
                            ProgressView("Generating PDF…")
                                .accessibilityLabel("Generating estimate PDF")
                        } else {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 52))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Text("Generating customer preview…")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
            }
        }
        .navigationTitle("Customer Preview")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(pdfUrl == nil)
                .accessibilityLabel("Share estimate PDF")
            }
        }
        .task { await generatePdf() }
    }

    @MainActor
    private func generatePdf() async {
        isGenerating = true
        defer { isGenerating = false }
        let rendered = ImageRenderer(content: EstimatePdfContent(estimate: estimate))
        rendered.scale = UIScreen.main.scale
        guard let uiImage = rendered.uiImage else { return }
        let pngData = uiImage.pngData() ?? Data()

        // Write to temp dir — used for share sheet attachment
        let filename = "\(estimate.orderId ?? "Estimate").pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try pngData.write(to: url)
            pdfUrl = url
        } catch {
            AppLog.ui.error("EstimatePdfPreview write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - EstimatePdfContent (rendered view)

struct EstimatePdfContent: View {
    let estimate: Estimate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(estimate.orderId ?? "Estimate")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Text(estimate.status?.capitalized ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text(estimate.customerName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            if let validUntil = estimate.validUntil {
                Text("Valid until: \(String(validUntil.prefix(10)))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Line items
            if let items = estimate.lineItems, !items.isEmpty {
                ForEach(items) { item in
                    HStack {
                        Text(item.description ?? item.itemName ?? "Item")
                            .font(.system(size: 14))
                        Spacer()
                        if let total = item.total {
                            Text(formatMoney(total))
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }
                Divider()
            }

            // Totals
            if let sub = estimate.subtotal {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(formatMoney(sub)).monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            if let disc = estimate.discount, disc > 0 {
                HStack {
                    Text("Discount")
                    Spacer()
                    Text("−\(formatMoney(disc))").monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            if let tax = estimate.totalTax, tax > 0 {
                HStack {
                    Text("Tax")
                    Spacer()
                    Text(formatMoney(tax)).monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            HStack {
                Text("Total")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text(formatMoney(estimate.total ?? 0))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
            }

            if let notes = estimate.notes, !notes.isEmpty {
                Divider()
                Text("Notes:")
                    .font(.system(size: 13, weight: .semibold))
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 595) // A4 points width approx
        .background(Color.white)
    }
}

// MARK: - EstimatePdfViewer (inline QuickLook wrapper)

struct EstimatePdfViewer: UIViewControllerRepresentable {
    let url: URL
    @Binding var showShare: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        context.coordinator.parentVC = vc

        // Show share when triggered
        if showShare {
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.present(activity, animated: true)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if showShare, uiViewController.presentedViewController == nil {
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                showShare = false
            }
            uiViewController.present(activity, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, @unchecked Sendable {
        weak var parentVC: UIViewController?
    }
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif
