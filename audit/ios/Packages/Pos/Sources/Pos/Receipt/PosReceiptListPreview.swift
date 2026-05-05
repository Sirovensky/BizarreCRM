#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Monospace receipt block rendered in JetBrains Mono. Shows the
/// plain-text receipt produced by `PosReceiptRenderer.text(_:)`.
///
/// Used as a preview-before-share surface so the cashier can confirm the
/// receipt content before dispatching SMS or email.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────┐
/// │  Receipt #NNNNN          [Sent ✓]    │  ← header (uppercased label + chip)
/// ├──────────────────────────────────────┤
/// │  ······  perforation  ·······        │
/// │  JetBrains Mono body                 │
/// │  ······  perforation  ·······        │
/// ├──────────────────────────────────────┤
/// │  Thank you · 30-day returns…         │  ← footer (if provided)
/// └──────────────────────────────────────┘
/// ```
public struct PosReceiptListPreview: View {
    public let receiptText: String

    /// E.g. "28014" — displayed as "RECEIPT #28014" in the header. `nil` hides the header row.
    public let receiptNumber: String?

    /// When non-nil a success chip ("Sent ✓") is shown in the header. Pass the
    /// channel label e.g. "Sent ✓" or "Sent via SMS ✓".
    public let sentChipLabel: String?

    /// Optional footer text. Matches mockup "Thank you · 30-day returns with receipt".
    public let footerText: String?

    public init(
        receiptText: String,
        receiptNumber: String? = nil,
        sentChipLabel: String? = nil,
        footerText: String? = nil
    ) {
        self.receiptText = receiptText
        self.receiptNumber = receiptNumber
        self.sentChipLabel = sentChipLabel
        self.footerText = footerText
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // Header row — "RECEIPT #28014" + optional "Sent ✓" chip
                if let num = receiptNumber {
                    HStack {
                        Text("Receipt #\(num)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textCase(.uppercase)
                            .kerning(0.8)
                        Spacer(minLength: BrandSpacing.xs)
                        if let chip = sentChipLabel {
                            Text(chip)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreSuccess)
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, 2)
                                .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.bizarreSuccess.opacity(0.3), lineWidth: 0.5))
                                .accessibilityLabel(chip)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .padding(.bottom, BrandSpacing.xs)

                    Divider()
                        .background(Color.bizarreOutline.opacity(0.25))
                }

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

                // Footer note
                if let footer = footerText, !footer.isEmpty {
                    Divider()
                        .background(Color.bizarreOutline.opacity(0.25))
                    Text(footer)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.xs)
                        .padding(.bottom, BrandSpacing.sm)
                        .accessibilityIdentifier("pos.receiptPreview.footer")
                }
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
        """,
        receiptNumber: "28014",
        sentChipLabel: "Sent ✓",
        footerText: "Thank you · 30-day returns with receipt"
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
