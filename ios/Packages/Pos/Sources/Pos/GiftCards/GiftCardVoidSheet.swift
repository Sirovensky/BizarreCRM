#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §40.4 — Gift-card void sheet with manager-PIN gate.
///
/// Voiding a gift card is a destructive, irreversible action. The flow:
/// 1. Manager taps "Void" on the GiftCardLookupView / GiftCardBalanceCard.
/// 2. `GiftCardVoidSheet` presents.
/// 3. Cashier enters reason.
/// 4. `ManagerPinSheet` overlays for PIN confirmation.
/// 5. On approval, the void is recorded in `GiftCardAuditLog`.
/// 6. The caller's `onVoided` closure fires (triggers `voidGiftCard` API call).
///
/// The actual network call is deferred to the caller so this sheet stays
/// testable without a live APIClient.
@MainActor
public struct GiftCardVoidSheet: View {

    /// Last 4 digits or full code of the card being voided.
    public let cardCode: String

    /// Current balance of the card, in cents.
    public let balanceCents: Int

    /// Called when the manager has approved and the void is confirmed.
    /// The caller is responsible for the network call.
    public let onVoided: (_ managerId: String, _ reason: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = ""
    @State private var showManagerPin: Bool = false
    @State private var approvedManagerId: String?

    public init(
        cardCode: String,
        balanceCents: Int,
        onVoided: @escaping (_ managerId: String, _ reason: String) -> Void
    ) {
        self.cardCode = cardCode
        self.balanceCents = balanceCents
        self.onVoided = onVoided
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                // Warning card
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreError)
                        .accessibilityHidden(true)
                    Text("Void Gift Card?")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Card ending in \(lastFour) · Balance: \(CartMath.formatCents(balanceCents))")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("This action is irreversible. The card will be permanently deactivated and its balance forfeited.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, BrandSpacing.md)
                .padding(.horizontal, BrandSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.bizarreError.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, BrandSpacing.base)

                // Reason input
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Reason *")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    TextField("Required — why is this card being voided?", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                        )
                        .accessibilityLabel("Void reason")
                        .accessibilityIdentifier("pos.giftCardVoid.reason")
                }
                .padding(.horizontal, BrandSpacing.base)

                // Manager PIN note
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Manager PIN required to confirm void")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()
            }
            .padding(.top, BrandSpacing.lg)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Void Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showManagerPin = true
                    } label: {
                        Label("Void", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.bizarreError)
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("pos.giftCardVoid.requestPin")
                }
            }
            .sheet(isPresented: $showManagerPin) {
                ManagerPinSheet { managerId in
                    approvedManagerId = managerId
                    commitVoid(managerId: managerId)
                }
            }
        }
    }

    // MARK: - Helpers

    private var lastFour: String {
        if cardCode.count <= 4 { return cardCode }
        return String(cardCode.suffix(4))
    }

    private func commitVoid(managerId: String) {
        let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
        // Write to audit log first (fire-and-forget is safe for local store)
        Task {
            await GiftCardAuditLog.shared.record(
                kind: .voided,
                cardCode: cardCode,
                amountCents: -balanceCents,  // negative = funds removed
                balanceCents: 0,
                approvedByManagerId: managerId
            )
        }
        BrandHaptics.success()
        AppLog.pos.info("Gift card void approved: card=\(cardCode) manager=\(managerId)")
        onVoided(managerId, trimmedReason)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Void sheet") {
    GiftCardVoidSheet(
        cardCode: "ABCD-1234",
        balanceCents: 5000
    ) { managerId, reason in
        print("Voided: manager=\(managerId) reason=\(reason)")
    }
    .preferredColorScheme(.dark)
}
#endif
