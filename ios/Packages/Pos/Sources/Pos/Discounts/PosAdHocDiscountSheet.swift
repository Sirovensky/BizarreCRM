#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

// MARK: - PosAdHocDiscountSheet (§16 — Manual override)
//
// When "Cashier-initiated ad-hoc discount" is permitted (tenant config
// `PosTenantLimits.allowCashierAdHocDiscount`), this sheet lets the cashier
// add a one-off discount without going through the manager-PIN flow — up to
// `PosTenantLimits.maxCashierDiscountPercent` / `maxCashierDiscountCents`.
//
// If the entered amount exceeds the cashier's ceiling, or if the tenant
// requires manager approval for ALL manual discounts, the sheet presents
// `ManagerPinSheet` before applying.
//
// On confirmation the discount is applied to the cart and a
// `discount_override` event is appended to `PosAuditLogStore` with:
//   - actor:          cashier (managerId = nil unless PIN used)
//   - amountCents:    the applied discount
//   - context.reason: the DiscountReasonCode raw value
//   - context.note:   free-text note
//   - context.type:   "cashier_adhoc" | "manager_override"

/// Describes the kind of ad-hoc manual discount the cashier is entering.
public enum AdHocDiscountKind: Sendable, Equatable {
    case percent(Double)   // 0.0–1.0
    case flat(Int)         // cents
}

/// Payload produced when the cashier confirms a manual discount.
public struct AdHocDiscountConfirmation: Sendable, Equatable {
    public let kind: AdHocDiscountKind
    /// Cents to deduct from the cart total.
    public let amountCents: Int
    public let reason: DiscountReasonCode
    public let note: String
    /// `true` when a manager PIN was entered to authorise the discount.
    public let requiresManagerApproval: Bool
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PosAdHocDiscountViewModel {

    // MARK: - Form state

    public var usePercent: Bool = true
    public var percentInput: String = ""
    public var flatInput: String = ""
    public var reason: DiscountReasonCode = .managerCourtesy
    public var note: String = ""

    // MARK: - Config

    /// Cart subtotal cents — used to compute flat-discount ceiling and % preview.
    public let cartSubtotalCents: Int

    /// Maximum cashier-level discount percent (0.0–1.0). Amounts above this
    /// require manager PIN.
    public let maxCashierPercent: Double

    /// Maximum cashier-level flat discount in cents.
    public let maxCashierCents: Int

    // MARK: - Derived

    public init(
        cartSubtotalCents: Int,
        maxCashierPercent: Double = 0.10,
        maxCashierCents: Int = 5_00
    ) {
        self.cartSubtotalCents = cartSubtotalCents
        self.maxCashierPercent = maxCashierPercent
        self.maxCashierCents = maxCashierCents
    }

    public var parsedPercent: Double? {
        guard usePercent,
              let v = Double(percentInput),
              v > 0, v <= 100 else { return nil }
        return v / 100.0
    }

    public var parsedFlatCents: Int? {
        guard !usePercent,
              let v = Int(flatInput),
              v > 0 else { return nil }
        return v
    }

    public var discountCents: Int? {
        if let p = parsedPercent {
            return Int((Double(cartSubtotalCents) * p).rounded())
        }
        return parsedFlatCents
    }

    /// Whether the requested discount exceeds the cashier's allowed ceiling.
    public var requiresManagerApproval: Bool {
        guard let cents = discountCents else { return false }
        if usePercent, let p = parsedPercent {
            return p > maxCashierPercent
        }
        return cents > maxCashierCents
    }

    public var canProceed: Bool {
        discountCents != nil
            && !(reason == .other && note.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    public var inputError: String? {
        guard let cents = discountCents else {
            if usePercent && !percentInput.isEmpty { return "Enter a valid percentage (1–100)" }
            if !usePercent && !flatInput.isEmpty { return "Enter a valid amount" }
            return nil
        }
        if cents > cartSubtotalCents { return "Discount exceeds cart total" }
        return nil
    }

    public func buildConfirmation(managerPinUsed: Bool) -> AdHocDiscountConfirmation? {
        guard let cents = discountCents, inputError == nil else { return nil }
        let kind: AdHocDiscountKind = usePercent
            ? .percent(parsedPercent ?? 0)
            : .flat(cents)
        return AdHocDiscountConfirmation(
            kind: kind,
            amountCents: cents,
            reason: reason,
            note: note.trimmingCharacters(in: .whitespaces),
            requiresManagerApproval: managerPinUsed
        )
    }
}

// MARK: - View

/// §16 — Cashier-initiated ad-hoc discount sheet.
///
/// Presented when the cashier taps "Manual discount" from the cart overflow menu.
/// Role-gated at the call site (`pos.apply_discount`).
public struct PosAdHocDiscountSheet: View {

    @Bindable public var vm: PosAdHocDiscountViewModel
    public let onConfirm: (AdHocDiscountConfirmation) -> Void
    public let onCancel: () -> Void

    @State private var showManagerPin: Bool = false
    @Environment(\.posTheme) private var theme
    @FocusState private var focused: Field?

    private enum Field: Hashable { case percent, flat, note }

    public init(
        vm: PosAdHocDiscountViewModel,
        onConfirm: @escaping (AdHocDiscountConfirmation) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.vm = vm
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .padding(.top, BrandSpacing.xl)
                    .accessibilityHidden(true)
                Text("Manual discount")
                    .font(.brandTitleLarge())
                    .foregroundStyle(theme.on)
                if let cents = vm.discountCents {
                    Text("− \(CartMath.formatCents(cents))")
                        .font(.brandDisplayMedium())
                        .foregroundStyle(theme.success)
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom, BrandSpacing.lg)

            ScrollView {
                VStack(spacing: BrandSpacing.md) {

                    // % / $ toggle
                    Picker("Discount type", selection: $vm.usePercent) {
                        Text("Percentage").tag(true)
                        Text("Fixed $").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pos.adhocDiscount.typePicker")

                    // Amount input
                    if vm.usePercent {
                        amountField(
                            label: "Percentage",
                            placeholder: "e.g. 10",
                            text: $vm.percentInput,
                            field: .percent,
                            suffix: "%"
                        )
                    } else {
                        amountField(
                            label: "Amount",
                            placeholder: "e.g. 500 (= $5.00)",
                            text: $vm.flatInput,
                            field: .flat,
                            suffix: "¢"
                        )
                    }

                    if let err = vm.inputError {
                        Text(err)
                            .font(.brandBodySmall())
                            .foregroundStyle(theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, BrandSpacing.sm)
                            .accessibilityLabel("Error: \(err)")
                    }

                    // Manager PIN required banner
                    if vm.requiresManagerApproval {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(theme.warning)
                                .accessibilityHidden(true)
                            Text("This discount exceeds your limit — manager PIN required.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(theme.on)
                        }
                        .padding(BrandSpacing.md)
                        .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Manager PIN required for this discount amount.")
                    }

                    // Reason picker
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Reason *")
                            .font(.brandLabelSmall())
                            .foregroundStyle(theme.muted)
                            .textCase(.uppercase)
                            .kerning(0.8)
                        Picker("Reason", selection: $vm.reason) {
                            ForEach(DiscountReasonCode.allCases, id: \.self) { code in
                                Label(code.displayName, systemImage: code.iconName)
                                    .tag(code)
                            }
                        }
                        .tint(theme.primary)
                        .pickerStyle(.menu)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("pos.adhocDiscount.reasonPicker")
                    }

                    // Note field (required for .other)
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(vm.reason == .other ? "Note *" : "Note (optional)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(theme.muted)
                            .textCase(.uppercase)
                            .kerning(0.8)
                        TextField("Explain the discount", text: $vm.note, axis: .vertical)
                            .lineLimit(3)
                            .focused($focused, equals: .note)
                            .font(.brandBodyLarge())
                            .foregroundStyle(theme.on)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.sm)
                            .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        focused == .note ? theme.primary.opacity(0.6) : theme.outline,
                                        lineWidth: 1
                                    )
                            )
                            .accessibilityLabel("Discount note\(vm.reason == .other ? ", required" : ", optional")")
                            .accessibilityIdentifier("pos.adhocDiscount.note")
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.lg)
                .animation(.spring(response: 0.22), value: vm.usePercent)
                .animation(.spring(response: 0.22), value: vm.discountCents)
            }

            // Footer
            Divider()
            HStack(spacing: BrandSpacing.sm) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .accessibilityIdentifier("pos.adhocDiscount.cancel")

                Button {
                    focused = nil
                    if vm.requiresManagerApproval {
                        showManagerPin = true
                    } else {
                        applyDiscount(managerPinUsed: false)
                    }
                } label: {
                    Label(
                        vm.requiresManagerApproval ? "Manager PIN →" : "Apply",
                        systemImage: vm.requiresManagerApproval ? "lock.shield" : "checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.requiresManagerApproval ? theme.warning : theme.primary)
                .disabled(!vm.canProceed || vm.inputError != nil)
                .controlSize(.large)
                .accessibilityIdentifier("pos.adhocDiscount.apply")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
            .background(theme.bg)
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Approve ad-hoc discount",
                onApproved: { _ in
                    showManagerPin = false
                    applyDiscount(managerPinUsed: true)
                },
                onCancelled: {
                    showManagerPin = false
                }
            )
        }
    }

    // MARK: - Helpers

    private func amountField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("\(label) *")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .kerning(0.8)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.numberPad)
                    .focused($focused, equals: field)
                    .font(.brandBodyLarge())
                    .foregroundStyle(theme.on)
                Text(suffix)
                    .font(.brandBodyLarge())
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        focused == field ? theme.primary.opacity(0.6) : theme.outline,
                        lineWidth: 1
                    )
            )
            .accessibilityLabel(label)
            .accessibilityIdentifier("pos.adhocDiscount.\(label.lowercased())")
        }
    }

    private func applyDiscount(managerPinUsed: Bool) {
        guard let confirmation = vm.buildConfirmation(managerPinUsed: managerPinUsed) else { return }
        BrandHaptics.success()
        Task {
            try? await PosAuditLogStore.shared.record(
                event: PosAuditEntry.EventType.discountOverride,
                cashierId: 0,
                managerId: managerPinUsed ? 0 : nil,
                amountCents: confirmation.amountCents,
                context: [
                    "reason":  confirmation.reason.rawValue,
                    "note":    confirmation.note,
                    "type":    managerPinUsed ? "manager_override" : "cashier_adhoc"
                ]
            )
        }
        onConfirm(confirmation)
    }
}

// MARK: - Preview

#Preview("Ad-hoc discount — cashier") {
    PosAdHocDiscountSheet(
        vm: PosAdHocDiscountViewModel(cartSubtotalCents: 15000),
        onConfirm: { conf in print("Confirmed: \(conf)") },
        onCancel: { print("Cancelled") }
    )
    .preferredColorScheme(.dark)
}
#endif
