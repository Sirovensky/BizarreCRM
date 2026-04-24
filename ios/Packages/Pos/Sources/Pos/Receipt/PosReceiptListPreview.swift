#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Monospace receipt block rendered in JetBrains Mono. Shows the
/// plain-text receipt produced by `PosReceiptRenderer.text(_:)`.
///
/// Used as a preview-before-share surface so the cashier can confirm the
/// receipt content before dispatching SMS or email.
///
/// Layout: ScrollView with a `Text` in `.brandMono(size: 12)`, padded inside
/// a glass card so it reads as a physical receipt slip.
public struct PosReceiptListPreview: View {
    public let receiptText: String

    public init(receiptText: String) {
        self.receiptText = receiptText
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Perforation line at the top
                perforationLine

                Text(receiptText)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurface)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.md)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pos.receiptPreview.body")

                // Perforation line at the bottom
                perforationLine
            }
            .background(Color.bizarreSurface1.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
            )
        }
        .accessibilityLabel("Receipt preview")
        .accessibilityIdentifier("pos.receiptPreview")
    }

    private var perforationLine: some View {
        HStack(spacing: 4) {
            ForEach(0..<22, id: \.self) { _ in
                Capsule()
                    .fill(Color.bizarreOutline.opacity(0.4))
                    .frame(width: 6, height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityHidden(true)
    }
}

#Preview {
    PosReceiptListPreview(
        receiptText: """
        BizarreCRM Demo
        123 Main St, Springfield
        (555) 867-5309
        2026-04-24 14:32

        Customer: Jane Smith
        Order: INV-0042

        iPhone Screen Replacement
          $89.99
        Tempered Glass x2
          $23.98 @ $11.99
          Line discount: -$2.00
          SKU: ACC-112

        Subtotal: $113.97
        Discount: -$2.00
        Tax: $9.12
        Total: $121.09

        Cash: $130.00
        Change: -$8.91

        Thank you for your business!
        """
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
