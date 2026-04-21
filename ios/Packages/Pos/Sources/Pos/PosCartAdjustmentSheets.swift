#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

// MARK: - §16.3 Discount Sheet

/// Cart-level discount sheet. Segmented "Amount $" / "Percent %" tabs.
/// Preset chips (5/10/15/20% in percent mode, $5/$10/$20 in dollar mode).
/// Apply button calls the appropriate `Cart` mutator and dismisses.
struct PosCartDiscountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: Cart

    enum DiscountMode: String, CaseIterable, Identifiable {
        case percent = "Percent %"
        case amount  = "Amount $"
        var id: String { rawValue }
    }

    @State private var mode: DiscountMode = .percent
    @State private var rawInput: String = ""
    @FocusState private var isInputFocused: Bool

    /// §16.11 — manager PIN gate state.
    @State private var showingManagerPin: Bool = false
    /// Pending apply values held while waiting for manager approval.
    @State private var pendingMode: DiscountMode? = nil
    @State private var pendingValue: Double? = nil

    private let percentPresets: [Double] = [0.05, 0.10, 0.15, 0.20]
    private let dollarPresetsCents: [Int] = [500, 1000, 2000]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    Picker("Mode", selection: $mode) {
                        ForEach(DiscountMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.md)

                    presetsRow
                    inputRow
                    previewRow
                    Spacer()
                }
            }
            .navigationTitle("Cart Discount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("pos.cartDiscount.apply")
                }
            }
            .onChange(of: mode) { _, _ in rawInput = "" }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
        // §16.11 — nested manager PIN sheet when discount exceeds cashier ceiling.
        .sheet(isPresented: $showingManagerPin) {
            if let pMode = pendingMode, let pValue = pendingValue {
                let limits = PosTenantLimits.current()
                let reasonText = pMode == .percent
                    ? "Discount \(Int(pValue))% exceeds cashier limit of \(Int(limits.maxCashierDiscountPercent))%"
                    : "Discount \(CartMath.formatCents(Int((pValue * 100).rounded()))) exceeds cashier limit of \(CartMath.formatCents(limits.maxCashierDiscountCents))"
                ManagerPinSheet(
                    reason: reasonText,
                    onApproved: { managerId in
                        commitDiscount(mode: pMode, value: pValue, managerId: managerId)
                        pendingMode = nil; pendingValue = nil
                    },
                    onCancelled: {
                        pendingMode = nil; pendingValue = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                if mode == .percent {
                    ForEach(percentPresets, id: \.self) { p in
                        presetChip(label: "\(Int(p * 100))%") {
                            rawInput = "\(Int(p * 100))"
                        }
                    }
                } else {
                    ForEach(dollarPresetsCents, id: \.self) { cents in
                        let dollars = cents / 100
                        presetChip(label: "$\(dollars)") {
                            rawInput = "\(dollars)"
                        }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private func presetChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreOrangeContainer, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inputRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(mode == .percent ? "%" : "$")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField(mode == .percent ? "e.g. 10" : "e.g. 5.00", text: $rawInput)
                .keyboardType(.decimalPad)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .focused($isInputFocused)
                .monospacedDigit()
                .accessibilityIdentifier("pos.cartDiscount.input")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.base)
        .onAppear { isInputFocused = true }
    }

    @ViewBuilder
    private var previewRow: some View {
        if let preview = previewText {
            HStack {
                Text("Discount")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(preview)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
            .padding(.horizontal, BrandSpacing.base)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Discount preview: \(preview)")
            .accessibilityIdentifier("pos.cartDiscount.preview")
        }
    }

    private var parsedValue: Double? {
        Double(rawInput.trimmingCharacters(in: .whitespaces))
    }

    private var isValid: Bool {
        guard let v = parsedValue, v > 0 else { return false }
        if mode == .percent { return v <= 100 }
        let cents = Int((v * 100).rounded())
        return cents > 0
    }

    private var previewText: String? {
        guard let v = parsedValue, v > 0 else { return nil }
        if mode == .percent {
            let percent = min(v, 100) / 100.0
            let discountCents = Int((Double(cart.subtotalCents) * percent).rounded())
            return "-\(CartMath.formatCents(discountCents))"
        } else {
            let cents = Int((v * 100).rounded())
            return "-\(CartMath.formatCents(cents))"
        }
    }

    private func applyAndDismiss() {
        guard let v = parsedValue, v > 0 else { return }
        let limits = PosTenantLimits.current()

        // §16.11 — Discount ceiling check.
        let exceedsCeiling: Bool
        if mode == .percent {
            exceedsCeiling = v > limits.maxCashierDiscountPercent
        } else {
            let cents = Int((v * 100).rounded())
            exceedsCeiling = cents > limits.maxCashierDiscountCents
        }

        if exceedsCeiling {
            // Hold the pending values and ask for manager PIN before committing.
            pendingMode = mode
            pendingValue = v
            showingManagerPin = true
            return
        }

        // Under the ceiling — apply directly without manager approval.
        commitDiscount(mode: mode, value: v, managerId: nil)
    }

    /// Apply the discount to the cart and emit the audit event.
    private func commitDiscount(mode: DiscountMode, value: Double, managerId: Int64?) {
        BrandHaptics.success()

        let originalCents = cart.effectiveDiscountCents
        if mode == .percent {
            let percent = min(value, 100) / 100.0
            cart.setCartDiscountPercent(percent)
        } else {
            let cents = Int((value * 100).rounded())
            cart.setCartDiscount(cents: cents)
        }
        let appliedCents = cart.effectiveDiscountCents

        // §16.11 — log discount_override when manager approved; otherwise no log
        // (ordinary under-threshold discounts are not audited to keep the log signal-rich).
        if let mId = managerId {
            Task {
                try? await PosAuditLogStore.shared.record(
                    event: PosAuditEntry.EventType.discountOverride,
                    cashierId: 0,
                    managerId: mId,
                    amountCents: appliedCents,
                    context: [
                        "originalCents": originalCents,
                        "appliedCents": appliedCents
                    ]
                )
            }
        }

        dismiss()
    }
}

// MARK: - §16.3 Tip Sheet

/// Cart-level tip sheet. Chips for 10/15/20% plus custom amount entry.
struct PosCartTipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: Cart

    @State private var rawInput: String = ""
    @State private var selectedPercent: Double? = nil
    @FocusState private var isInputFocused: Bool

    private let percentPresets: [Double] = [0.10, 0.15, 0.20]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    tipPresetsRow
                        .padding(.top, BrandSpacing.md)
                    customInputRow
                    previewRow
                    Spacer()
                }
            }
            .navigationTitle("Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("pos.cartTip.apply")
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
    }

    private var tipPresetsRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(percentPresets, id: \.self) { p in
                let isSelected = selectedPercent == p && rawInput.isEmpty
                Button {
                    BrandHaptics.tap()
                    selectedPercent = p
                    rawInput = ""
                } label: {
                    VStack(spacing: 4) {
                        Text("\(Int(p * 100))%")
                            .font(.brandTitleSmall())
                            .foregroundStyle(isSelected ? .white : .bizarreOrange)
                        let tipCents = Int((Double(cart.subtotalCents) * p).rounded())
                        Text(CartMath.formatCents(tipCents))
                            .font(.brandLabelSmall())
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(isSelected ? Color.bizarreOrange : Color.bizarreOrangeContainer, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(p * 100))% tip, \(CartMath.formatCents(Int((Double(cart.subtotalCents) * p).rounded())))")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    private var customInputRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Custom amount")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)
            HStack(spacing: BrandSpacing.sm) {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $rawInput)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .focused($isInputFocused)
                    .monospacedDigit()
                    .onChange(of: rawInput) { _, _ in
                        if !rawInput.isEmpty { selectedPercent = nil }
                    }
                    .accessibilityIdentifier("pos.cartTip.input")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    @ViewBuilder
    private var previewRow: some View {
        if let preview = previewText {
            HStack {
                Text("Tip")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("+\(preview)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
            .padding(.horizontal, BrandSpacing.base)
            .accessibilityIdentifier("pos.cartTip.preview")
        }
    }

    private var isValid: Bool {
        if let p = selectedPercent, rawInput.isEmpty { return p > 0 }
        guard let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 else { return false }
        return true
    }

    private var previewText: String? {
        if let p = selectedPercent, rawInput.isEmpty {
            let cents = Int((Double(cart.subtotalCents) * p).rounded())
            return CartMath.formatCents(cents)
        }
        guard let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return CartMath.formatCents(Int((v * 100).rounded()))
    }

    private func applyAndDismiss() {
        BrandHaptics.success()
        if let p = selectedPercent, rawInput.isEmpty {
            cart.setTipPercent(p)
        } else if let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 {
            cart.setTip(cents: Int((v * 100).rounded()))
        }
        dismiss()
    }
}

// MARK: - §16.3 Fees Sheet

/// Cart-level fees sheet. Cents input + optional label (60-char max).
struct PosCartFeesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: Cart

    @State private var rawInput: String = ""
    @State private var label: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    amountRow
                        .padding(.top, BrandSpacing.md)
                    labelRow
                    previewRow
                    Spacer()
                }
            }
            .navigationTitle("Fee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("pos.cartFees.apply")
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
        .onAppear { isInputFocused = true }
    }

    private var amountRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Amount")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)
            HStack(spacing: BrandSpacing.sm) {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $rawInput)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .focused($isInputFocused)
                    .monospacedDigit()
                    .accessibilityIdentifier("pos.cartFees.input")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private var labelRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Label (optional)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)
            TextField("e.g. Delivery fee", text: $label)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .onChange(of: label) { _, new in
                    if new.count > 60 { label = String(new.prefix(60)) }
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityIdentifier("pos.cartFees.label")
        }
    }

    @ViewBuilder
    private var previewRow: some View {
        if let preview = previewText {
            HStack {
                Text(label.isEmpty ? "Fee" : label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                Spacer()
                Text("+\(preview)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .padding(.horizontal, BrandSpacing.base)
            .accessibilityIdentifier("pos.cartFees.preview")
        }
    }

    private var isValid: Bool {
        guard let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 else { return false }
        return true
    }

    private var previewText: String? {
        guard let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return CartMath.formatCents(Int((v * 100).rounded()))
    }

    private func applyAndDismiss() {
        guard let v = Double(rawInput.trimmingCharacters(in: .whitespaces)), v > 0 else { return }
        BrandHaptics.success()
        let cents = Int((v * 100).rounded())
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        cart.setFees(cents: cents, label: trimmedLabel.isEmpty ? nil : trimmedLabel)
        dismiss()
    }
}
#endif
