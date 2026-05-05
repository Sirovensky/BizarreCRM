#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - DiscountReasonCode

/// Predefined reason codes for a manual manager-authorised discount.
///
/// The raw value is the server-canonical code stored in the sale payload and
/// audit log — keep it stable (no renames after shipping).
public enum DiscountReasonCode: String, CaseIterable, Sendable, Hashable {
    case customerLoyalty   = "customer_loyalty"
    case priceMatch        = "price_match"
    case damageOrDefect    = "damage_or_defect"
    case employeeDiscount  = "employee_discount"
    case promotionalEvent  = "promotional_event"
    case managerCourtesy   = "manager_courtesy"
    case other             = "other"

    /// Display label shown in the picker.
    public var displayName: String {
        switch self {
        case .customerLoyalty:  return "Customer loyalty"
        case .priceMatch:       return "Price match"
        case .damageOrDefect:   return "Damage / defect"
        case .employeeDiscount: return "Employee discount"
        case .promotionalEvent: return "Promotional event"
        case .managerCourtesy:  return "Manager courtesy"
        case .other:            return "Other"
        }
    }

    /// SF Symbol name for visual distinction in the picker.
    public var iconName: String {
        switch self {
        case .customerLoyalty:  return "heart.fill"
        case .priceMatch:       return "equal.circle.fill"
        case .damageOrDefect:   return "exclamationmark.triangle.fill"
        case .employeeDiscount: return "person.badge.key.fill"
        case .promotionalEvent: return "megaphone.fill"
        case .managerCourtesy:  return "hand.thumbsup.fill"
        case .other:            return "ellipsis.circle.fill"
        }
    }
}

// MARK: - DiscountApplyRequest

/// Payload produced by `DiscountApplySheet` when the cashier taps "Apply".
///
/// All fields are non-optional so the caller can write them directly to the
/// sale payload without extra guard-let chains.
public struct DiscountApplyRequest: Sendable, Equatable {
    /// The discount amount in cents.
    public let discountCents: Int
    /// Whether it's a percentage (`true`) or flat-cents (`false`) discount.
    public let isPercent: Bool
    /// The raw percentage value (0.0–1.0) when `isPercent == true`; otherwise `nil`.
    public let discountPercent: Double?
    /// Reason code chosen by the manager.
    public let reasonCode: DiscountReasonCode
    /// Optional free-text note entered alongside the picker selection.
    public let note: String
    /// The manager ID who approved (placeholder 0 until real manager identity ships).
    public let managerId: Int64
}

// MARK: - DiscountApplyViewModel

/// Drives `DiscountApplySheet`. Handles form validation and PIN verification.
@MainActor
@Observable
public final class DiscountApplyViewModel {

    // MARK: - Form state

    /// Whether the discount is entered as a percentage (`true`) or fixed cents (`false`).
    public var usePercent: Bool = true

    /// Raw string for percentage input (e.g. "10" = 10 %).
    public var percentInput: String = "" {
        didSet { validateInput() }
    }

    /// Raw string for flat-cents input (e.g. "500" = $5.00).
    public var flatCentsInput: String = "" {
        didSet { validateInput() }
    }

    /// Selected reason code.
    public var reasonCode: DiscountReasonCode = .managerCourtesy

    /// Optional free-text note (required when `reasonCode == .other`).
    public var note: String = ""

    // MARK: - Approval state

    public enum ApprovalState: Equatable {
        /// Waiting for the cashier to fill the form.
        case pendingForm
        /// Manager PIN entry in progress.
        case pendingPin
        /// PIN verified — discount approved.
        case approved(DiscountApplyRequest)
        /// Validation or PIN error.
        case error(String)
    }

    public private(set) var approvalState: ApprovalState = .pendingForm
    public private(set) var inputError: String? = nil

    // MARK: - Computed

    public var parsedPercent: Double? {
        guard usePercent, let v = Double(percentInput), v > 0, v <= 100 else { return nil }
        return v / 100.0
    }

    public var parsedFlatCents: Int? {
        guard !usePercent, let v = Int(flatCentsInput), v > 0 else { return nil }
        return v
    }

    public var canProceed: Bool {
        inputError == nil
            && (parsedPercent != nil || parsedFlatCents != nil)
            && !(reasonCode == .other && note.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Actions

    /// Move the sheet into PIN-entry mode.
    public func requestPinApproval() {
        validateInput()
        guard canProceed else { return }
        approvalState = .pendingPin
    }

    /// Called by the embedded `ManagerPinSheet` on success.
    public func managerApproved(managerId: Int64, subtotalCents: Int) {
        let discountCents: Int
        let isPercent: Bool
        let percent: Double?

        if let pct = parsedPercent {
            isPercent = true
            percent = pct
            discountCents = min(Int((Double(subtotalCents) * pct).rounded()), subtotalCents)
        } else if let flat = parsedFlatCents {
            isPercent = false
            percent = nil
            discountCents = min(flat, subtotalCents)
        } else {
            approvalState = .error("Invalid discount value.")
            return
        }

        let request = DiscountApplyRequest(
            discountCents: discountCents,
            isPercent: isPercent,
            discountPercent: percent,
            reasonCode: reasonCode,
            note: note.trimmingCharacters(in: .whitespaces),
            managerId: managerId
        )
        approvalState = .approved(request)
    }

    /// Called when the manager cancels PIN entry.
    public func managerCancelled() {
        approvalState = .pendingForm
    }

    // MARK: - Private

    private func validateInput() {
        if usePercent {
            guard let v = Double(percentInput) else {
                inputError = percentInput.isEmpty ? nil : "Enter a number between 1 and 100."
                return
            }
            inputError = (v > 0 && v <= 100) ? nil : "Percentage must be between 1 and 100."
        } else {
            guard let v = Int(flatCentsInput) else {
                inputError = flatCentsInput.isEmpty ? nil : "Enter a whole number of cents."
                return
            }
            inputError = v > 0 ? nil : "Discount must be greater than zero."
        }
    }
}

// MARK: - DiscountApplySheet

/// Manager-authorised manual discount sheet.
///
/// ## Flow
/// 1. Cashier fills discount value + reason code (+ note when reason is "Other").
/// 2. Tapping "Apply" shows the embedded `ManagerPinSheet`.
/// 3. On PIN approval `onApplied` is called with the fully-formed `DiscountApplyRequest`.
///
/// ## Design
/// - `bizarreSurfaceBase` full-bleed background (same as every POS sheet).
/// - Liquid Glass chrome on toolbar (`.brandGlass` on the navigation bar area
///   via the system toolbar — no manual overlay needed here).
/// - `.medium` + `.large` detent to accommodate the reason-code picker on small devices.
/// - Reason-code picker uses a `List`-embedded `ForEach` so VoiceOver can swipe
///   through each option without a custom control.
public struct DiscountApplySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var vm = DiscountApplyViewModel()
    @State private var showPin = false

    /// Cart subtotal in cents — used to compute the actual cents amount when
    /// the cashier entered a percentage.
    public let subtotalCents: Int

    /// Called when the manager approves and the discount is ready to apply.
    public let onApplied: @MainActor (DiscountApplyRequest) -> Void

    public init(
        subtotalCents: Int,
        onApplied: @escaping @MainActor (DiscountApplyRequest) -> Void
    ) {
        self.subtotalCents = subtotalCents
        self.onApplied = onApplied
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.xl) {
                        headerBadge
                        discountSection
                        reasonSection
                        if vm.reasonCode == .other {
                            noteSection
                        }
                        applyButton
                        Spacer(minLength: BrandSpacing.xxl)
                    }
                    .padding(.top, BrandSpacing.lg)
                    .padding(.horizontal, BrandSpacing.base)
                }
            }
            .navigationTitle("Manual Discount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("discountApply.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showPin) {
            ManagerPinSheet(
                reason: pinReason,
                onApproved: { managerId in
                    vm.managerApproved(managerId: managerId, subtotalCents: subtotalCents)
                    showPin = false
                    if case .approved(let req) = vm.approvalState {
                        onApplied(req)
                        dismiss()
                    }
                },
                onCancelled: {
                    vm.managerCancelled()
                    showPin = false
                }
            )
        }
    }

    // MARK: - Sub-views

    private var headerBadge: some View {
        Image(systemName: "percent")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(.bizarreOrange)
            .accessibilityHidden(true)
    }

    private var discountSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Discount amount")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Picker("Type", selection: $vm.usePercent) {
                Text("Percentage").tag(true)
                Text("Fixed amount").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("discountApply.typePicker")

            if vm.usePercent {
                percentField
            } else {
                flatField
            }

            if let err = vm.inputError {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("discountApply.inputError")
            }
        }
    }

    private var percentField: some View {
        HStack {
            TextField("e.g. 10", text: $vm.percentInput)
                .keyboardType(.decimalPad)
                .font(.brandHeadlineMedium().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Discount percentage")
                .accessibilityIdentifier("discountApply.percentField")
            Text("%")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(fieldBorderColor, lineWidth: 1.5)
        )
    }

    private var flatField: some View {
        HStack {
            Text("¢")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("e.g. 500 = $5.00", text: $vm.flatCentsInput)
                .keyboardType(.numberPad)
                .font(.brandHeadlineMedium().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Discount amount in cents")
                .accessibilityIdentifier("discountApply.flatField")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(fieldBorderColor, lineWidth: 1.5)
        )
    }

    private var fieldBorderColor: Color {
        vm.inputError != nil
            ? Color.bizarreError.opacity(0.7)
            : Color.bizarreOutline.opacity(0.5)
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            VStack(spacing: 0) {
                ForEach(DiscountReasonCode.allCases, id: \.self) { code in
                    reasonRow(code)
                    if code != DiscountReasonCode.allCases.last {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .accessibilityIdentifier("discountApply.reasonPicker")
        }
    }

    private func reasonRow(_ code: DiscountReasonCode) -> some View {
        Button {
            vm.reasonCode = code
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: code.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(vm.reasonCode == code ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(code.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if vm.reasonCode == code {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(code.displayName)
        .accessibilityAddTraits(vm.reasonCode == code ? .isSelected : [])
        .accessibilityIdentifier("discountApply.reason.\(code.rawValue)")
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Note (required)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Describe the reason…", text: $vm.note, axis: .vertical)
                .lineLimit(3...5)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Discount reason note")
                .accessibilityIdentifier("discountApply.noteField")
        }
    }

    private var applyButton: some View {
        Button {
            vm.requestPinApproval()
            if case .pendingPin = vm.approvalState {
                showPin = true
            }
        } label: {
            HStack {
                Image(systemName: "person.badge.key.fill")
                    .accessibilityHidden(true)
                Text("Apply — Manager approval required")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.brandGlassProminent)
        .disabled(!vm.canProceed)
        .accessibilityIdentifier("discountApply.applyButton")
    }

    // MARK: - Helpers

    private var pinReason: String {
        let amount: String
        if vm.usePercent, let pct = vm.parsedPercent {
            let display = String(format: "%.0f%%", pct * 100)
            amount = "\(display) off"
        } else if let flat = vm.parsedFlatCents {
            amount = "\(CartMath.formatCents(flat, currencyCode: "USD")) off"
        } else {
            amount = "manual discount"
        }
        return "Approve \(amount) — \(vm.reasonCode.displayName)"
    }
}

#endif
