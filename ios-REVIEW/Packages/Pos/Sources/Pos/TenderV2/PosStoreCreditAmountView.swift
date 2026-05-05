#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Store credit balance apply view.
///
/// Displays the customer's available store-credit balance (fetched from
/// `GET /api/v1/customers/:id/wallet` — existing `WalletEndpoints`).
/// The cashier can apply up to the lesser of (balance, dueCents).
///
/// Full store-credit redemption lives in `GiftCards/` (existing). This view
/// owns only the tender-entry surface.
public struct PosStoreCreditAmountView: View {

    /// Amount due for this leg (cents).
    public let dueCents: Int

    /// Available store-credit balance in cents (nil = still loading).
    public let availableBalanceCents: Int?

    /// Called with the amount to apply. `reference` is the customer id string.
    public let onConfirm: (_ amountCents: Int, _ reference: String?) -> Void

    /// Called if the cashier cancels.
    public let onCancel: () -> Void

    @State private var applyFullBalance: Bool = true
    @State private var customCents: Int = 0

    @Environment(\.posTheme) private var theme

    public init(
        dueCents: Int,
        availableBalanceCents: Int?,
        onConfirm: @escaping (_ amountCents: Int, _ reference: String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.availableBalanceCents = availableBalanceCents
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Computed

    private var maxApplicable: Int {
        guard let balance = availableBalanceCents else { return 0 }
        return min(balance, dueCents)
    }

    private var amountToApply: Int {
        applyFullBalance ? maxApplicable : min(customCents, maxApplicable)
    }

    private var canConfirm: Bool {
        amountToApply > 0
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    // Header
                    VStack(spacing: BrandSpacing.xxs) {
                        Text("Store credit")
                            .font(.brandLabelLarge())
                            .foregroundStyle(theme.muted)
                        Text(CartMath.formatCents(dueCents))
                            .font(.brandDisplayMedium())
                            .foregroundStyle(theme.on)
                            .monospacedDigit()
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .accessibilityIdentifier("pos.storeCreditV2.amount")
                    }
                    .padding(.top, BrandSpacing.xl)

                    // Balance card
                    balanceCard
                        .padding(.horizontal, BrandSpacing.base)

                    // Apply toggle
                    if availableBalanceCents != nil {
                        applySection
                            .padding(.horizontal, BrandSpacing.base)
                    }
                }
            }

            // Confirm button
            Button {
                onConfirm(amountToApply, nil)
            } label: {
                Text("Apply \(CartMath.formatCents(amountToApply))")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
                    .foregroundStyle(canConfirm ? theme.onPrimary : theme.muted)
            }
            .buttonStyle(.borderedProminent)
            .tint(canConfirm ? theme.primary : theme.surfaceElev)
            .disabled(!canConfirm)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .padding(.top, BrandSpacing.sm)
            .accessibilityIdentifier("pos.storeCreditV2.applyButton")
        }
        .background(theme.bg.ignoresSafeArea())
    }

    // MARK: - Balance card

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Available balance")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
                if let balance = availableBalanceCents {
                    Text(CartMath.formatCents(balance))
                        .font(.brandHeadlineLarge())
                        .foregroundStyle(theme.on)
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .accessibilityIdentifier("pos.storeCreditV2.balance")
                } else {
                    ProgressView()
                        .tint(theme.primary)
                        .accessibilityLabel("Loading balance")
                }
            }
            Spacer()
            Image(systemName: "person.badge.clock.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.teal)
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.base)
        .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.outline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available store credit balance: \(availableBalanceCents.map { CartMath.formatCents($0) } ?? "loading")")
    }

    // MARK: - Apply section

    private var applySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Toggle(isOn: $applyFullBalance) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Apply maximum")
                        .font(.brandLabelLarge())
                        .foregroundStyle(theme.on)
                    Text(CartMath.formatCents(maxApplicable))
                        .font(.brandBodyMedium())
                        .foregroundStyle(theme.muted)
                }
            }
            .tint(theme.primary)
            .accessibilityIdentifier("pos.storeCreditV2.applyMaxToggle")
        }
        .padding(BrandSpacing.base)
        .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.outline, lineWidth: 0.5)
        )
    }
}
#endif
