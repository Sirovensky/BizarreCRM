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
    public let onTap: () -> Void

    public init(pickup: ReadyPickup, onTap: @escaping () -> Void) {
        self.pickup = pickup
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkmark badge — mockup: 32×32, corner radius 9
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.bizarreSuccess.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.bizarreSuccess.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.bizarreSuccess)
                }
                .accessibilityHidden(true)

                // Name + ticket info
                VStack(alignment: .leading, spacing: 2) {
                    Text(pickup.customerName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(1)
                    if let device = pickup.deviceSummary {
                        Text("#\(pickup.orderId) · \(device)")
                            .font(.caption)
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    } else {
                        Text("#\(pickup.orderId)")
                            .font(.caption)
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Amount — mockup: BarlowCondensed-SemiBold 17pt, primary color
                Text(pickup.totalFormatted)
                    .font(.custom("BarlowCondensed-SemiBold", size: 17, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityLabel("Total: \(pickup.totalFormatted)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bizarreSuccess.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.bizarreSuccess.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pickup.customerName), ready for pickup, ticket \(pickup.orderId), \(pickup.totalFormatted)"
        )
        .accessibilityHint("Tap to open ticket")
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview {
    PickupRow(
        pickup: ReadyPickup(
            id: 4829,
            orderId: "4829",
            customerName: "Sarah M.",
            deviceSummary: "iPhone 14 · Screen repair",
            totalCents: 27400
        ),
        onTap: {}
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
#endif
