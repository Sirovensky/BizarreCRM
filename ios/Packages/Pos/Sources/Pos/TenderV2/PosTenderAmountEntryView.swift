#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Step 2 of the v2 tender flow: amount entry dispatcher.
///
/// This view reads `coordinator.method` and dispatches to the correct
/// method-specific sub-view:
/// - `.cash`        → `PosCashAmountView`
/// - `.card`        → `PosCardAmountView`
/// - `.giftCard`    → `PosGiftCardAmountView`
/// - `.storeCredit` → `PosStoreCreditAmountView`
/// - `.check`       → `PosCheckTenderSheet` (§16.6)
///
/// Each sub-view calls `coordinator.applyTender(amountCents:reference:)` on
/// confirmation, which handles the partial/full-payment state transition.
public struct PosTenderAmountEntryView: View {

    @Bindable public var coordinator: PosTenderCoordinator

    /// Customer store-credit balance for the `.storeCredit` sub-view.
    /// Pass `nil` to show a loading state; resolve via `WalletEndpoints`.
    public let storeCreditBalanceCents: Int?

    @Environment(\.posTheme) private var theme

    public init(
        coordinator: PosTenderCoordinator,
        storeCreditBalanceCents: Int? = nil
    ) {
        self.coordinator = coordinator
        self.storeCreditBalanceCents = storeCreditBalanceCents
    }

    public var body: some View {
        Group {
            switch coordinator.method {
            case .cash:
                PosCashAmountView(
                    dueCents: coordinator.remaining,
                    onConfirm: { receivedCents in
                        coordinator.applyTender(amountCents: receivedCents)
                    },
                    onCancel: {
                        coordinator.cancelAmountEntry()
                    }
                )
            case .card:
                PosCardAmountView(
                    dueCents: coordinator.remaining,
                    onConfirm: { amountCents, reference in
                        coordinator.applyTender(amountCents: amountCents, reference: reference)
                    },
                    onCancel: {
                        coordinator.cancelAmountEntry()
                    }
                )
            case .giftCard:
                PosGiftCardAmountView(
                    dueCents: coordinator.remaining,
                    onConfirm: { amountCents, reference in
                        coordinator.applyTender(amountCents: amountCents, reference: reference)
                    },
                    onCancel: {
                        coordinator.cancelAmountEntry()
                    }
                )
            case .storeCredit:
                PosStoreCreditAmountView(
                    dueCents: coordinator.remaining,
                    availableBalanceCents: storeCreditBalanceCents,
                    onConfirm: { amountCents, reference in
                        coordinator.applyTender(amountCents: amountCents, reference: reference)
                    },
                    onCancel: {
                        coordinator.cancelAmountEntry()
                    }
                )
            case .check:
                // §16.6 — Check tender. Full amount is applied; no partial
                // check entry (the cashier can do a second leg if needed).
                PosCheckTenderSheet(
                    dueCents: coordinator.remaining,
                    onConfirm: { amountCents, reference in
                        coordinator.applyTender(amountCents: amountCents, reference: reference)
                    },
                    onCancel: {
                        coordinator.cancelAmountEntry()
                    }
                )
            case nil:
                // Should not happen — parent only shows this view when a
                // method is selected. Fallback to a progress indicator.
                ProgressView()
                    .tint(theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
#endif
