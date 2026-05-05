#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.6 — Check / bank-check tender sheet.
///
/// The cashier enters the check number, the issuing bank name, and an optional
/// memo. No payment auth is required — the transaction goes to A/R (Accounts
/// Receivable) on the server side. No PAN or sensitive data is captured here.
///
/// Role gate: `pos.accept_check` is enforced at the call site (same as
/// account-credit) — not repeated here to avoid double-gating.
///
/// Accessibility: all input fields labelled; form submits on ⌘Return.
@MainActor
public struct PosCheckTenderSheet: View {

    /// Amount due for this tender leg, in cents.
    public let dueCents: Int

    /// Called when the cashier confirms — delivers the check details as
    /// the `reference` string so the receipt and audit log carry check #.
    public let onConfirm: (_ amountCents: Int, _ reference: String) -> Void

    /// Called when the cashier cancels and returns to the method picker.
    public let onCancel: () -> Void

    @State private var checkNumber: String = ""
    @State private var bankName: String = ""
    @State private var memo: String = ""
    @FocusState private var focusedField: Field?

    @Environment(\.posTheme) private var theme

    public init(
        dueCents: Int,
        onConfirm: @escaping (_ amountCents: Int, _ reference: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private enum Field: Hashable { case checkNum, bank, memo }

    private var canConfirm: Bool {
        !checkNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var referenceString: String {
        var parts = ["Check #\(checkNumber.trimmingCharacters(in: .whitespaces))"]
        let bank = bankName.trimmingCharacters(in: .whitespaces)
        if !bank.isEmpty { parts.append("Bank: \(bank)") }
        let m = memo.trimmingCharacters(in: .whitespaces)
        if !m.isEmpty { parts.append("Memo: \(m)") }
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .padding(.top, BrandSpacing.xl)
                    .accessibilityHidden(true)
                Text("Check payment")
                    .font(.brandTitleLarge())
                    .foregroundStyle(theme.on)
                Text(CartMath.formatCents(dueCents))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                Text("Goes to A/R — no auth required")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .padding(.top, BrandSpacing.xxs)
            }
            .padding(.bottom, BrandSpacing.lg)

            // Form
            ScrollView {
                VStack(spacing: BrandSpacing.md) {
                    fieldRow(
                        label: "Check number",
                        placeholder: "e.g. 1042",
                        text: $checkNumber,
                        field: .checkNum,
                        keyboardType: .numbersAndPunctuation,
                        required: true
                    )
                    fieldRow(
                        label: "Bank name",
                        placeholder: "e.g. First National Bank",
                        text: $bankName,
                        field: .bank,
                        keyboardType: .default,
                        required: false
                    )
                    fieldRow(
                        label: "Memo",
                        placeholder: "Optional note",
                        text: $memo,
                        field: .memo,
                        keyboardType: .default,
                        required: false
                    )
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
                        .accessibilityIdentifier("pos.checkTender.cancel")

                    Button {
                        guard canConfirm else { return }
                        BrandHaptics.success()
                        onConfirm(dueCents, referenceString)
                    } label: {
                        Text("Confirm check")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primary)
                    .disabled(!canConfirm)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Confirm check tender for \(CartMath.formatCents(dueCents))")
                    .accessibilityIdentifier("pos.checkTender.confirm")
                }
                .controlSize(.large)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
            .background(theme.bg)
        }
        .background(theme.bg.ignoresSafeArea())
        .onSubmit { advanceFocus() }
    }

    // MARK: - Helpers

    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboardType: UIKeyboardType,
        required: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(required ? "\(label) *" : label)
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .kerning(0.8)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .submitLabel(field == .memo ? .done : .next)
                .focused($focusedField, equals: field)
                .font(.brandBodyLarge())
                .foregroundStyle(theme.on)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            focusedField == field ? theme.primary.opacity(0.6) : theme.outline,
                            lineWidth: 1
                        )
                )
                .accessibilityLabel(label)
                .accessibilityIdentifier("pos.checkTender.\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
        }
    }

    private func advanceFocus() {
        switch focusedField {
        case .checkNum: focusedField = .bank
        case .bank: focusedField = .memo
        default: focusedField = nil
        }
    }
}

// MARK: - Preview
#Preview("Check tender") {
    PosCheckTenderSheet(
        dueCents: 8750,
        onConfirm: { amount, ref in
            print("Confirmed: \(amount) ref=\(ref)")
        },
        onCancel: { print("Cancelled") }
    )
    .preferredColorScheme(.dark)
}
#endif
