#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosCustomerContextBanners
//
// §16.4 Customer-context banners shown below the customer header in the
// POS cart panel when the attached customer has special attributes:
//
//   1. Group discount — auto-applied; amber banner ("Group discount applied: X%")
//   2. Tax exemption — green banner ("Tax exempt · Cert: XXXXX")
//   3. Loyalty points preview — info banner ("You'll earn N points")
//
// Rules:
//   - Banners are informational only — no tappable state inside the banner
//     itself (except a tap-to-dismiss after 5s auto-hide, deferred).
//   - Never shown when customerContext == .empty (no customer attached).
//   - Always use `.bizarreOnSurface` text on coloured pill backgrounds so the
//     banners pass WCAG AA contrast at any Dynamic Type size.
//   - Banners stack vertically (not overlaid); only non-nil contexts render.

public struct PosCustomerContextBanners: View {
    let context: PosCustomerContext
    let cartTotalCents: Int
    /// When non-nil, passed to PosViewModel.loyaltyPointsPreview. Supplying
    /// it here avoids importing PosViewModel in every call site — caller
    /// passes the computed value directly.
    let earnedPoints: Int?

    public init(context: PosCustomerContext, cartTotalCents: Int, earnedPoints: Int? = nil) {
        self.context = context
        self.cartTotalCents = cartTotalCents
        self.earnedPoints = earnedPoints
    }

    public var body: some View {
        if context == .empty {
            EmptyView()
        } else {
            VStack(spacing: BrandSpacing.xs) {
                groupDiscountBanner
                taxExemptBanner
                loyaltyBanner
            }
        }
    }

    // MARK: - Group discount banner (§16.4 Customer-specific pricing)

    @ViewBuilder
    private var groupDiscountBanner: some View {
        if let pct = context.groupDiscountPercent, pct > 0 {
            let display = Int((pct * 100).rounded())
            contextBanner(
                icon: "tag.fill",
                message: "Group discount applied: \(display)%"
                    + (context.groupName.map { " · \($0)" } ?? ""),
                background: Color.bizarreOrange.opacity(0.15),
                iconColor: .bizarreOrange
            )
            .accessibilityIdentifier("pos.banner.groupDiscount")
        }
    }

    // MARK: - Tax-exempt banner (§16.4 Tax exemption)

    @ViewBuilder
    private var taxExemptBanner: some View {
        if context.isTaxExempt {
            let cert = context.exemptionCertNumber.map { " · Cert: \($0)" } ?? ""
            contextBanner(
                icon: "checkmark.seal.fill",
                message: "Tax exempt\(cert)",
                background: Color.bizarreSuccess.opacity(0.13),
                iconColor: .bizarreSuccess
            )
            .accessibilityIdentifier("pos.banner.taxExempt")
        }
    }

    // MARK: - Loyalty earn preview (§16.4 Loyalty points preview)

    @ViewBuilder
    private var loyaltyBanner: some View {
        if let pts = earnedPoints, pts > 0 {
            contextBanner(
                icon: "star.fill",
                message: "You'll earn \(pts) point\(pts == 1 ? "" : "s") on this sale",
                background: Color.bizarreTeal.opacity(0.13),
                iconColor: .bizarreTeal
            )
            .accessibilityIdentifier("pos.banner.loyaltyEarn")
        } else if let balance = context.loyaltyPointsBalance {
            contextBanner(
                icon: "star.circle",
                message: "Loyalty balance: \(balance) point\(balance == 1 ? "" : "s")",
                background: Color.bizarreTeal.opacity(0.10),
                iconColor: .bizarreTeal
            )
            .accessibilityIdentifier("pos.banner.loyaltyBalance")
        }
    }

    // MARK: - Shared banner chrome

    private func contextBanner(
        icon: String,
        message: String,
        background: Color,
        iconColor: Color
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(background, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("All banners") {
    PosCustomerContextBanners(
        context: PosCustomerContext(
            groupDiscountPercent: 0.15,
            groupName: "VIP Members",
            isTaxExempt: true,
            exemptionCertNumber: "TX-2024-8891",
            loyaltyPointsBalance: 420,
            loyaltyPointsPerDollar: 1.5
        ),
        cartTotalCents: 5000,
        earnedPoints: 75
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Loyalty only") {
    PosCustomerContextBanners(
        context: PosCustomerContext(loyaltyPointsBalance: 120),
        cartTotalCents: 3000
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif

#endif // canImport(UIKit)
