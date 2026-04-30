#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.6 — Account credit / net-30 tender sheet.
///
/// Role-gated: only presented when `pos.accept_account_credit` is in the user's
/// role. The caller must enforce the gate + `ManagerPinSheet` before pushing
/// this view. The cashier confirms customer terms, optionally enters a PO
/// number, and the full amount is applied to the customer's open A/R balance.
/// No payment auth is performed.
///
/// Server writes: the tender leg is submitted as `payment_method: "account_credit"`
/// in `POST /api/v1/pos/transaction` → server adds to customer open balance.
@MainActor
public struct PosAccountCreditTenderSheet: View {

    // MARK: - Inputs

    /// Remaining balance due for this tender leg, in cents.
    public let dueCents: Int

    /// Customer name to show in the confirmation header.
    public let customerName: String

    /// Whether this customer has `net_terms` configured on the server.
    /// When `false` the sheet shows a blocking warning and disables Confirm.
    public let customerHasTerms: Bool

    /// Called when the cashier confirms — delivers the PO reference string.
    public let onConfirm: (_ amountCents: Int, _ reference: String) -> Void

    /// Called when the cashier cancels and returns to the method picker.
    public let onCancel: () -> Void

    // MARK: - State

    @State private var poNumber: String = ""
    @State private var termsAcknowledged: Bool = false
    @FocusState private var poFieldFocused: Bool

    @Environment(\.posTheme) private var theme

    public init(
        dueCents: Int,
        customerName: String,
        customerHasTerms: Bool,
        onConfirm: @escaping (_ amountCents: Int, _ reference: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.customerName = customerName
        self.customerHasTerms = customerHasTerms
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Helpers

    private var canConfirm: Bool {
        customerHasTerms && termsAcknowledged
    }

    private var referenceString: String {
        let po = poNumber.trimmingCharacters(in: .whitespaces)
        if po.isEmpty {
            return "Net-30 / Account credit — \(customerName)"
        }
        return "Net-30 / PO# \(po) — \(customerName)"
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .padding(.top, BrandSpacing.xl)
                    .accessibilityHidden(true)
                Text("Account / Net-30")
                    .font(.brandTitleLarge())
                    .foregroundStyle(theme.on)
                Text(CartMath.formatCents(dueCents))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                Text("Added to open balance · no payment auth")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .padding(.top, BrandSpacing.xxs)
            }
            .padding(.bottom, BrandSpacing.lg)

            ScrollView {
                VStack(spacing: BrandSpacing.md) {

                    // No-terms warning
                    if !customerHasTerms {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.warning)
                                .accessibilityHidden(true)
                            Text("This customer has no net terms on file. Configure terms in customer settings before using this tender.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(theme.on)
                        }
                        .padding(BrandSpacing.md)
                        .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Warning: customer has no net terms configured.")
                    }

                    // Customer name row
                    HStack {
                        Text("Customer")
                            .font(.brandLabelSmall())
                            .foregroundStyle(theme.muted)
                            .textCase(.uppercase)
                            .kerning(0.8)
                        Spacer()
                        Text(customerName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(theme.on)
                    }
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))

                    // PO number field (optional)
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("PO number (optional)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(theme.muted)
                            .textCase(.uppercase)
                            .kerning(0.8)
                        TextField("e.g. PO-2026-042", text: $poNumber)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.done)
                            .focused($poFieldFocused)
                            .font(.brandBodyLarge())
                            .foregroundStyle(theme.on)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.sm)
                            .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        poFieldFocused ? theme.primary.opacity(0.6) : theme.outline,
                                        lineWidth: 1
                                    )
                            )
                            .accessibilityLabel("PO number, optional")
                            .accessibilityIdentifier("pos.accountCredit.poNumber")
                    }

                    // Terms acknowledgment toggle
                    Toggle(isOn: $termsAcknowledged) {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text("Customer has approved this charge")
                                .font(.brandBodyMedium())
                                .foregroundStyle(theme.on)
                            Text("Confirm the customer acknowledges net-30 payment terms apply.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(theme.muted)
                        }
                    }
                    .tint(theme.primary)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Customer has approved net-30 charge")
                    .accessibilityIdentifier("pos.accountCredit.termsToggle")
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.lg)
            }

            // Footer CTA
            Divider()
            VStack(spacing: BrandSpacing.sm) {
                HStack(spacing: BrandSpacing.sm) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("pos.accountCredit.cancel")

                    Button {
                        guard canConfirm else { return }
                        BrandHaptics.success()
                        poFieldFocused = false
                        onConfirm(dueCents, referenceString)
                    } label: {
                        Text("Add to A/R balance")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primary)
                    .disabled(!canConfirm)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Add \(CartMath.formatCents(dueCents)) to account receivable balance")
                    .accessibilityIdentifier("pos.accountCredit.confirm")
                }
                .controlSize(.large)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
            .background(theme.bg)
        }
        .background(theme.bg.ignoresSafeArea())
        .onSubmit { poFieldFocused = false }
    }
}

// MARK: - Preview

#Preview("Account credit — terms OK") {
    PosAccountCreditTenderSheet(
        dueCents: 27451,
        customerName: "Acme Corp",
        customerHasTerms: true,
        onConfirm: { amount, ref in print("Confirmed: \(amount) ref=\(ref)") },
        onCancel: { print("Cancelled") }
    )
    .preferredColorScheme(.dark)
}

#Preview("Account credit — no terms") {
    PosAccountCreditTenderSheet(
        dueCents: 27451,
        customerName: "New Customer",
        customerHasTerms: false,
        onConfirm: { _, _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
#endif
