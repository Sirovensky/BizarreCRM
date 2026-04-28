#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosGiftCardOfflineSheet (§16.12)

/// Presented when a cashier attempts to redeem a gift card while the device
/// is offline.
///
/// **Policy (§16.12):**
/// Gift-card balance lookup requires an internet connection — we cannot verify
/// the card's remaining balance locally. The cashier is offered two choices:
/// 1. **Cancel** — remove the gift-card tender and choose cash or check.
/// 2. **Accept as IOU (manager PIN required)** — accept the gift card for a
///    manager-specified amount without balance verification. A `PosSaleTenderRecord`
///    with `iouApproved: true` is written to the sale record; the discrepancy is
///    flagged in the dead-letter queue for manager review on reconnect.
///
/// iPhone: `.medium` detent sheet.
/// iPad: centred popover-style sheet at 420 pt width.
public struct PosGiftCardOfflineSheet: View {

    // MARK: - Inputs

    /// The gift-card code (or masked version) shown to the cashier.
    public let cardCode: String
    /// The remaining cart total (the maximum IOU amount the cashier can offer).
    public let cartTotalCents: Int
    /// Called when the cashier cancels (removes the gift-card tender leg).
    public let onCancel: () -> Void
    /// Called when a manager approves the IOU. Parameter is the agreed amount in cents.
    public let onIouApproved: (Int) -> Void

    // MARK: - Private state

    @Environment(\.dismiss) private var dismiss
    @State private var showManagerPin = false
    @State private var iouAmountCents: Int

    // MARK: - Init

    public init(
        cardCode: String,
        cartTotalCents: Int,
        onCancel: @escaping () -> Void,
        onIouApproved: @escaping (Int) -> Void
    ) {
        self.cardCode = cardCode
        self.cartTotalCents = cartTotalCents
        self.onCancel = onCancel
        self.onIouApproved = onIouApproved
        _iouAmountCents = State(wrappedValue: cartTotalCents)
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                offlineWarningSection
                iouSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Gift Card — Offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 420)
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Accept gift card \(cardCode.prefix(6))*** as IOU for \(CartMath.formatCents(iouAmountCents)).",
                onApproved: { _ in
                    onIouApproved(iouAmountCents)
                    dismiss()
                },
                onCancelled: { }
            )
        }
    }

    // MARK: - Sections

    private var offlineWarningSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Card balance lookup needs internet")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Gift card \(cardCode.prefix(6))*** cannot be verified offline. Balance and status are unknown.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } icon: {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.bizarreError)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gift card balance lookup requires internet connection")
            .accessibilityIdentifier("pos.giftCardOffline.warning")
        }
    }

    private var iouSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Accept as IOU (manager required)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("A manager can approve accepting this card for an unverified amount. The transaction will be flagged for review on reconnect.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                // Cents stepper — amounts from $0.01 to cart total
                HStack {
                    Text("IOU amount")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(CartMath.formatCents(iouAmountCents))
                        .font(.brandTitleSmall())
                        .foregroundStyle(Color.bizarrePrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(iouAmountCents)))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: iouAmountCents)
                }
                .accessibilityIdentifier("pos.giftCardOffline.iouAmount")

                Stepper(
                    value: $iouAmountCents,
                    in: 1...max(1, cartTotalCents),
                    step: 100  // $1 increments
                ) {
                    EmptyView()
                }
                .accessibilityLabel("IOU amount stepper, currently \(CartMath.formatCents(iouAmountCents))")
                .accessibilityIdentifier("pos.giftCardOffline.iouStepper")

                Button {
                    showManagerPin = true
                } label: {
                    Label("Require manager PIN to accept", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.bizarrePrimary)
                .accessibilityIdentifier("pos.giftCardOffline.acceptIou")
                .padding(.top, BrandSpacing.xs)
            }
            .listRowInsets(.init(top: BrandSpacing.md, leading: BrandSpacing.md, bottom: BrandSpacing.md, trailing: BrandSpacing.md))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Remove card tender") {
                onCancel()
                dismiss()
            }
            .foregroundStyle(.bizarreError)
            .accessibilityIdentifier("pos.giftCardOffline.cancel")
        }
    }
}
#endif
