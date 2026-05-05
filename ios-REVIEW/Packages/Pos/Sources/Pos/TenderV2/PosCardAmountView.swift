#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Card (Tap to Pay) placeholder view.
///
/// ProximityReader entitlement is pending. This view renders a branded
/// placeholder and TODO comments for the integration wave.
///
/// TODO (Tap to Pay wave):
///   1. Add `com.apple.developer.proximity-reader.payment.acceptance`
///      entitlement to `BizarreCRM.entitlements`.
///   2. Import `ProximityReader` framework.
///   3. Replace the `tapToPayPlaceholder` body with `PaymentCardReaderSession`
///      presented via the Proximity Reader API.
///   4. Wire `onConfirm` with the approved amount + auth code from the reader.
public struct PosCardAmountView: View {

    /// Amount the cashier is charging via card (cents).
    public let dueCents: Int

    /// Called when the card payment is approved. `reference` is the auth code.
    public let onConfirm: (_ amountCents: Int, _ reference: String?) -> Void

    /// Called if the cashier cancels and goes back to method picker.
    public let onCancel: () -> Void

    @Environment(\.posTheme) private var theme

    public init(
        dueCents: Int,
        onConfirm: @escaping (_ amountCents: Int, _ reference: String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

            tapToPayPlaceholder

            // Amount
            VStack(spacing: BrandSpacing.xxs) {
                Text("Card payment")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
                Text(CartMath.formatCents(dueCents))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityIdentifier("pos.cardAmountV2.amount")
            }

            // Coming-soon notice
            Text("Tap to Pay integration pending.\nProximityReader entitlement required.")
                .font(.brandBodyMedium())
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)

            Spacer()

            // For now, let the cashier manually confirm a card charge
            // (e.g., after using an external terminal). Remove this
            // button once ProximityReader is integrated.
            Button {
                onConfirm(dueCents, nil)
            } label: {
                Text("Mark as paid (manual)")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
                    .foregroundStyle(theme.onPrimary)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primary)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .accessibilityIdentifier("pos.cardAmountV2.manualConfirm")
        }
        .background(theme.bg.ignoresSafeArea())
        .accessibilityLabel("Card payment screen. Amount: \(CartMath.formatCents(dueCents)).")
    }

    // MARK: - Illustration

    private var tapToPayPlaceholder: some View {
        ZStack {
            Circle()
                .fill(theme.primarySoft)
                .frame(width: 120, height: 120)

            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(theme.primary)
        }
        .overlay(
            // "Coming soon" badge
            Text("TODO")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.onPrimary)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(theme.warning, in: Capsule())
                .offset(x: 40, y: -40)
        )
        .accessibilityHidden(true)
    }
}
#endif
