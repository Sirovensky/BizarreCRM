#if canImport(UIKit)
import SwiftUI
import CoreImage.CIFilterBuiltins
import Core
import DesignSystem

// MARK: - CouponQRView (§16 — QR coupons)
//
// Renders a printable / emailable flyer for a coupon code:
//   - QR code encoding the coupon code string
//   - Human-readable code below the QR (for manual entry fallback)
//   - Discount description + expiry
//   - "Scan or type at checkout" instruction
//
// Scanning the QR at the POS auto-fills the `CouponInputSheet` via
// `PosScanSheet` (the barcode scanner passes decoded strings to the
// coupon field — the cashier taps "Coupon" in the tender/cart sheet,
// which opens the scanner; decoded code is auto-submitted).
//
// This view is also used as the print/share payload for email / AirDrop.

public struct CouponQRView: View {

    public let coupon: CouponCode
    public let qrSize: CGFloat

    @State private var qrImage: UIImage? = nil

    public init(coupon: CouponCode, qrSize: CGFloat = 200) {
        self.coupon = coupon
        self.qrSize = qrSize
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            // QR code
            Group {
                if let img = qrImage {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: qrSize, height: qrSize)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: qrSize, height: qrSize)
                        .redacted(reason: .placeholder)
                }
            }
            .accessibilityLabel("Coupon QR code for \(coupon.code). Scan at checkout.")

            // Human-readable code
            VStack(spacing: BrandSpacing.xxs) {
                Text("COUPON CODE")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreMutedForeground)
                    .kerning(0.8)
                Text(coupon.code)
                    .font(.brandDisplaySmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("Coupon code: \(coupon.code)")
            }

            // Rule description
            if let desc = coupon.description {
                Text(desc)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
            } else {
                Text(coupon.ruleName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
            }

            // Expiry
            if let expires = coupon.expiresAt {
                Label(
                    "Expires \(expires.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreMutedForeground)
            }

            // Uses remaining
            if let uses = coupon.usesRemaining {
                Label(
                    "\(uses) use\(uses == 1 ? "" : "s") remaining",
                    systemImage: "number.circle"
                )
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreMutedForeground)
            }

            // Instruction
            Text("Scan at checkout or enter code manually")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreMutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: 360)
        .task(id: coupon.code) {
            qrImage = await generateQR(from: coupon.code, size: qrSize)
        }
    }

    // MARK: - QR generation

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

// MARK: - CouponQRShareView
//
// Full-screen flyer for print / share via `ShareLink` or `.sheet`.

public struct CouponQRShareView: View {

    public let coupon: CouponCode
    @Environment(\.dismiss) private var dismiss

    public init(coupon: CouponCode) {
        self.coupon = coupon
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                CouponQRView(coupon: coupon, qrSize: 240)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Coupon QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: coupon.code,
                        subject: Text("Coupon code: \(coupon.code)"),
                        message: Text("\(coupon.ruleName) — use code \(coupon.code) at checkout.")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Coupon QR flyer") {
    CouponQRShareView(
        coupon: CouponCode(
            id: "preview-1",
            code: "SAVE10",
            ruleId: "rule-1",
            ruleName: "10% off entire cart",
            usesRemaining: 47,
            perCustomerLimit: 1,
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            description: "10% off your entire purchase — valid for 14 days"
        )
    )
    .preferredColorScheme(.dark)
}
#endif
