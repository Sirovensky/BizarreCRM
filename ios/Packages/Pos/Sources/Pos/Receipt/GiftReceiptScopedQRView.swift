#if canImport(UIKit)
import SwiftUI
import CoreImage.CIFilterBuiltins
import Core
import DesignSystem

// MARK: - GiftReceiptScopedQRView (§16)
//
// Renders the one-time return QR code on a gift receipt.
//
// The QR encodes `returnURL` — a tokenised public URL that lets the recipient
// initiate a return without revealing the price or authenticating:
//   `https://app.bizarrecrm.com/returns/gift/<token>`
//
// The token is:
//   - Single-use: server marks it consumed on first return initiation.
//   - Price-opaque: the URL path contains only the token, never the amount.
//   - Scoped: the server links the token to this specific invoice + tenant.
//
// Usage in `GiftReceiptSheet` / printed receipt:
// ```swift
// if let returnURL = options.returnURL(baseURL: serverBaseURL) {
//     GiftReceiptScopedQRView(returnURL: returnURL)
// }
// ```

public struct GiftReceiptScopedQRView: View {

    public let returnURL: URL
    /// Side length for the rendered QR image; defaults to 160pt.
    public let size: CGFloat

    @State private var qrImage: UIImage? = nil

    public init(returnURL: URL, size: CGFloat = 160) {
        self.returnURL = returnURL
        self.size = size
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityLabel("Gift return QR code — scan to return this gift without revealing its price")
                    .accessibilityIdentifier("giftReceipt.returnQR")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }

            Text("Scan to return — no price revealed")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreMutedForeground)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .task(id: returnURL) {
            qrImage = await generateQR(from: returnURL.absoluteString, size: size)
        }
    }

    // MARK: - QR generation (off main actor)

    private func generateQR(from string: String, size: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(string.utf8)
            filter.correctionLevel = "M"
            guard let ciImage = filter.outputImage else { return nil }
            let scale = size / ciImage.extent.width
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

// MARK: - Preview

#Preview("Gift receipt QR") {
    GiftReceiptScopedQRView(
        returnURL: URL(string: "https://app.bizarrecrm.com/returns/gift/abc123-uuid-placeholder")!,
        size: 180
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
