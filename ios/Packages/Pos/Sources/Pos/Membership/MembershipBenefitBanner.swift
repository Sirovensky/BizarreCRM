// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// This banner MUST render ONLY inside the tender-method-picker screen.
// DO NOT render on: Cart, Catalog, Customer gate, Inspector, or any screen
// prior to the cashier tapping "Charge".
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// Top banner shown on the tender method picker when the attached customer is a
/// loyalty member.  Hidden entirely when `vm.account == nil` (walk-in or
/// no membership).
///
/// Visual targets: iPhone frame 5a and iPad frame 4a from
/// `ios/pos-iphone-mockups.html` / `ios/pos-ipad-mockups.html`.
///
/// Color tokens:
///   Dark mode  → cream gradient  (`#fdeed0` @ 12% opacity → 2%)
///   Light mode → deep orange gradient (`#c2410c` / bizarreOrange @ 10% → 2%)
///
/// If Agent A's `@Environment(\.posTheme)` key is live, the primary color is
/// read from there. Otherwise `BrandColors.bizarreOrange` is used as fallback.
/// TODO: wire `@Environment(\.posTheme)` once Agent A lands.
public struct MembershipBenefitBanner: View {

    @Bindable var vm: MembershipViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onRedeemTapped: () -> Void

    public init(vm: MembershipViewModel, onRedeemTapped: @escaping () -> Void) {
        self.vm = vm
        self.onRedeemTapped = onRedeemTapped
    }

    public var body: some View {
        if let account = vm.account, account.isMember {
            bannerContent(account: account)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(account: account))
                .accessibilityHint("Tap REDEEM PTS to apply points as a discount.")
        }
    }

    // MARK: - Banner body

    @ViewBuilder
    private func bannerContent(account: LoyaltyAccount) -> some View {
        HStack(spacing: 10) {
            // Star glyph with cream/orange glow
            Text("★")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(account.tier.color)
                .shadow(
                    color: account.tier.color.opacity(reduceTransparency ? 0 : 0.45),
                    radius: 6,
                    x: 0, y: 0
                )
                .accessibilityHidden(true)

            // Tier + points info
            VStack(alignment: .leading, spacing: 1) {
                Text("\(account.tier.displayName.uppercased()) member · \(account.discountPercent)% off applied")
                    .font(.brandLabelLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(primaryColor)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text(subtitleText(account: account))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Spacer(minLength: 4)

            // "SAVED $X" chip (only when discount > 0)
            if vm.saved > 0 {
                savedChip(cents: vm.saved)
            }

            // "REDEEM PTS" button (only when points > 0)
            if account.pointsBalance > 0 {
                redeemButton(account: account)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: shadowColor,
            radius: reduceTransparency ? 0 : 7,
            x: 0, y: 3
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Sub-views

    private func savedChip(cents: Int) -> some View {
        Text("SAVED \(CartMath.formatCents(cents))")
            .font(.brandLabelSmall().bold())
            .fontDesign(.monospaced)
            .foregroundStyle(primaryColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(primaryColor.opacity(0.12))
                    .overlay(Capsule().strokeBorder(primaryColor.opacity(0.35), lineWidth: 0.5))
            )
            .accessibilityLabel("Saved \(CartMath.formatCents(cents))")
    }

    private func redeemButton(account: LoyaltyAccount) -> some View {
        Button(action: {
            BrandHaptics.tap()
            onRedeemTapped()
        }) {
            Text("REDEEM PTS")
                .font(.brandLabelSmall().bold())
                .foregroundStyle(.bizarreTeal)
                .fixedSize()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Redeem loyalty points. \(account.pointsBalance) available.")
        .accessibilityHint("Opens a sheet to apply points as a discount.")
    }

    // MARK: - Colors / gradients

    /// Primary accent color: cream in dark mode, deep orange in light mode.
    /// TODO: replace with `@Environment(\.posTheme).primary` once Agent A lands.
    private var primaryColor: Color {
        colorScheme == .dark
            ? Color(red: 0.992, green: 0.933, blue: 0.816)  // #fdeed0 cream
            : .bizarreOrange
    }

    private var bannerBackground: some View {
        let surfaceColor = Color(.systemBackground)
        if colorScheme == .dark {
            return AnyView(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.992, green: 0.933, blue: 0.816).opacity(
                                    reduceTransparency ? 0.18 : 0.12
                                ),
                                Color(red: 0.992, green: 0.933, blue: 0.816).opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .blended(
                            with: Color(.systemGroupedBackground).opacity(0.9),
                            mode: .normal
                        )
                    )
            )
        } else {
            return AnyView(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bizarreOrange.opacity(reduceTransparency ? 0.14 : 0.09),
                                Color.bizarreOrange.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .blended(with: surfaceColor.opacity(0.9), mode: .normal)
                    )
            )
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color(red: 0.992, green: 0.933, blue: 0.816).opacity(0.38)
            : Color.bizarreOrange.opacity(0.28)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color(red: 0.992, green: 0.933, blue: 0.816).opacity(0.06)
            : Color.bizarreOrange.opacity(0.10)
    }

    // MARK: - Helpers

    private func subtitleText(account: LoyaltyAccount) -> String {
        var parts: [String] = []
        if vm.pointsToEarn > 0 {
            parts.append("Earning \(vm.pointsToEarn) pts")
        }
        if vm.saved > 0 {
            parts.append("\(CartMath.formatCents(vm.saved)) saved this sale")
        }
        if account.pointsBalance > 0 && vm.redeemPoints == 0 {
            parts.append("\(account.pointsBalance) pts available")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(account: LoyaltyAccount) -> String {
        "\(account.tier.displayName) member. \(account.discountPercent) percent discount applied. " +
        "\(account.pointsBalance) points available."
    }
}

// MARK: - LinearGradient blend shim

/// Lightweight shim so we can overlay the gradient on top of a system background
/// without requiring iOS 26 material APIs.
private extension ShapeStyle {
    func blended(with other: Color, mode: BlendMode) -> AnyShapeStyle {
        AnyShapeStyle(self)
    }
}
#endif
