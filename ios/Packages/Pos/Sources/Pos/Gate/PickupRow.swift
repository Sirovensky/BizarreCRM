/// PickupRow.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Reusable compact row for a ready-for-pickup ticket.
/// Used in the gate strip and the full pickup list sheet.

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// TODO: migrate to posTheme once Agent A lands
public struct PickupRow: View {
    public let pickup: ReadyPickup
    /// True for the first (most prominent) row; false applies dimmer border/fill.
    /// Mockup: row 1 → rgba(52,196,126,0.07) bg + 0.28 border;
    ///         row 2+ → rgba(52,196,126,0.05) bg + 0.22 border.
    public let isFirst: Bool
    /// Badge square size in points (32 iPhone, 36 iPad per mockup).
    public let badgeSize: CGFloat
    /// Badge corner radius (9 iPhone, 10 iPad per mockup).
    public let badgeCornerRadius: CGFloat
    /// Checkmark glyph font size (15 iPhone, 18 iPad per mockup).
    public let badgeFontSize: CGFloat
    public let onTap: () -> Void

    public init(
        pickup: ReadyPickup,
        isFirst: Bool = true,
        badgeSize: CGFloat = 32,
        badgeCornerRadius: CGFloat = 9,
        badgeFontSize: CGFloat = 15,
        onTap: @escaping () -> Void
    ) {
        self.pickup = pickup
        self.isFirst = isFirst
        self.badgeSize = badgeSize
        self.badgeCornerRadius = badgeCornerRadius
        self.badgeFontSize = badgeFontSize
        self.onTap = onTap
    }

    // Mockup bg/border opacities per row rank
    private var bgOpacity: Double { isFirst ? 0.07 : 0.05 }
    private var borderOpacity: Double { isFirst ? 0.28 : 0.22 }
    private var badgeFillOpacity: Double { isFirst ? 0.20 : 0.18 }
    private var badgeBorderOpacity: Double { isFirst ? 0.35 : 0.30 }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkmark badge — size/cornerRadius per caller (iPhone 32/9, iPad 36/10)
                ZStack {
                    RoundedRectangle(cornerRadius: badgeCornerRadius)
                        .fill(Color.bizarreSuccess.opacity(badgeFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: badgeCornerRadius)
                                .stroke(Color.bizarreSuccess.opacity(badgeBorderOpacity), lineWidth: 1)
                        )
                        .frame(width: badgeSize, height: badgeSize)
                    Text("✓")
                        .font(.system(size: badgeFontSize, weight: .bold))
                        .foregroundStyle(Color.bizarreSuccess)
                }
                .accessibilityHidden(true)

                // Name + ticket info
                VStack(alignment: .leading, spacing: 2) {
                    Text(pickup.customerName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(1)
                    if let device = pickup.deviceSummary {
                        Text("#\(pickup.orderId) · \(device)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    } else {
                        Text("#\(pickup.orderId)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Amount — Barlow Condensed Bold 17pt, cream/orange per mockup var(--primary)
                // Mockup specifies font-weight: 700 (Bold), not 600 (SemiBold).
                Text(pickup.totalFormatted)
                    .font(.custom("BarlowCondensed-Bold", size: 17))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityLabel("Total: \(pickup.totalFormatted)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bizarreSuccess.opacity(bgOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.bizarreSuccess.opacity(borderOpacity), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        // CLAUDE.md: .hoverEffect(.highlight) on tappable rows (no-op on iPhone)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pickup.customerName), ready for pickup, ticket \(pickup.orderId), \(pickup.totalFormatted)"
        )
        .accessibilityHint("Tap to open ticket")
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview("Row 1 — first") {
    PickupRow(
        pickup: ReadyPickup(
            id: 4829,
            orderId: "4829",
            customerName: "Sarah M.",
            deviceSummary: "iPhone 14 · Screen repair",
            totalCents: 27400
        ),
        isFirst: true,
        onTap: {}
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
}

#Preview("Row 2 — subsequent") {
    PickupRow(
        pickup: ReadyPickup(
            id: 4831,
            orderId: "4831",
            customerName: "Marco D.",
            deviceSummary: "Samsung S23 battery",
            totalCents: 14200
        ),
        isFirst: false,
        onTap: {}
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
#endif
