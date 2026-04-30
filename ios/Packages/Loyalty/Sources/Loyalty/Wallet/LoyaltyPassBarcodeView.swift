import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem

// MARK: - §38.4 Barcode on loyalty pass (scannable at POS)

/// Renders the loyalty pass barcode from a `LoyaltyPassInfo.barcode` string.
///
/// Uses CoreImage QR / Code-128 generation — no third-party SDK.
/// The barcode string is typically a UUID or numeric member ID that the
/// POS scanner reads to look up `GET /loyalty/balance/:customerId`.
///
/// ## Layout
///  - iPhone/POS: tall QR code centred in a glass card.
///  - iPad: QR + Code-128 side by side in a split card.
///
/// ## Accessibility
/// `.textSelection(.enabled)` on the raw barcode string so VoiceOver + keyboard
/// users can copy it; the image itself has an accessibility label.
public struct LoyaltyPassBarcodeView: View {
    let barcode: String
    let tier: LoyaltyTier
    let memberName: String

    public init(barcode: String, tier: LoyaltyTier, memberName: String) {
        self.barcode = barcode
        self.tier = tier
        self.memberName = memberName
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            // Header
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tier.systemSymbol)
                    .foregroundStyle(tier.displayColor)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(memberName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text("\(tier.displayName) Member")
                        .font(.brandLabelSmall())
                        .foregroundStyle(tier.displayColor)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(memberName), \(tier.displayName) loyalty member")

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // QR code
            if let qrImage = generateQR(barcode) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .accessibilityLabel("Loyalty QR code for \(memberName)")
                    .accessibilityHint("Show this to scan at the POS terminal")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bizarreSurface2)
                    .frame(width: 180, height: 180)
                    .overlay(Text("—").foregroundStyle(.bizarreOnSurfaceMuted))
            }

            // Raw barcode string (copyable)
            Text(barcode)
                .font(.brandMono(size: 13))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textSelection(.enabled)
                .accessibilityLabel("Barcode value: \(barcode)")
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
            .strokeBorder(tier.displayColor.opacity(0.3), lineWidth: 1))
    }

    // MARK: - CoreImage QR generation (no third-party SDK)

    private func generateQR(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.message = data
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }
        // Scale up for clarity
        let scale: CGFloat = 10
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
