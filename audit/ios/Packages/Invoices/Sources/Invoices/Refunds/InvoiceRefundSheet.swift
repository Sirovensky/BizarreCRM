#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.4 Invoice Refund Sheet
// iPhone: bottom sheet (.large). iPad: side panel (capped 540pt width).
// Refund type: refund / store_credit / credit_note.
// Manager PIN required when amount > $100.

public struct InvoiceRefundSheet: View {
    @State private var vm: InvoiceRefundViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSuccess: (RefundResult) -> Void

    public init(vm: InvoiceRefundViewModel, onSuccess: @escaping (RefundResult) -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public var body: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Issue Refund")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .applySheetBehavior(vm: vm, onSuccess: onSuccess, dismiss: dismiss)
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Issue Refund")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .frame(maxWidth: 540)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .applySheetBehavior(vm: vm, onSuccess: onSuccess, dismiss: dismiss)
    }

    // MARK: - Shared content

    private var sheetContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    paidSummary
                    refundTypeSection
                    amountModeToggle
                    if vm.useLineItems {
                        lineItemsSection
                    } else {
                        manualAmountSection
                    }
                    refundMethodSection
                    reasonSection
                    if vm.requiresManagerPin && !vm.managerPin.isEmpty {
                        pinConfirmedBadge
                    }
                    submitButton
                }
                .padding(BrandSpacing.base)
            }
        }
        .sheet(isPresented: $vm.showManagerPinPrompt) {
            ManagerPinSheet { pin in
                Task { await vm.submitWithPin(pin) }
            }
        }
    }

    @ToolbarContentBuilder
    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.bizarreOrange)
        }
    }

    // MARK: - Sections

    private var paidSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Total Paid")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.totalPaidCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("Refunding")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.effectiveAmountCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total paid \(formatCents(vm.totalPaidCents)). Refunding \(formatCents(vm.effectiveAmountCents)).")
    }

    private var refundTypeSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Refund Type")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Picker("Refund Type", selection: $vm.refundType) {
                ForEach(RefundType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Refund type selector")
        }
        .cardBackground()
    }

    private var amountModeToggle: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Refund Mode")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Picker("Refund Mode", selection: $vm.useLineItems) {
                Text("Total Amount").tag(false)
                Text("By Line Item").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Refund mode selector")
        }
        .cardBackground()
    }

    @ViewBuilder
    private var lineItemsSection: some View {
        if !vm.lineItems.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Select Items to Refund")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)

                ForEach($vm.lineItems) { $item in
                    HStack(spacing: BrandSpacing.sm) {
                        Toggle(isOn: $item.isSelected) {
                            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                Text(item.displayName)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(formatCents(item.totalCents))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkboxStyle)
                    }
                    .accessibilityLabel(
                        "\(item.displayName), \(formatCents(item.totalCents)). \(item.isSelected ? "Selected" : "Not selected")."
                    )
                }
            }
            .cardBackground()
        }
    }

    private var manualAmountSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Refund Amount")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                Text("$").font(.brandHeadlineMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.manualAmountString)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Refund amount in dollars")
            }

            if let err = vm.fieldErrors["amount"] {
                Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
            }
        }
        .cardBackground()
    }

    private var refundMethodSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Return Method")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(InvoiceTender.allCases) { t in
                        TenderChip(label: t.displayName, isSelected: vm.refundMethod == t) {
                            vm.refundMethod = t
                        }
                        .accessibilityLabel("\(t.displayName) refund method")
                        .accessibilityAddTraits(vm.refundMethod == t ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }
        }
        .cardBackground()
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Picker("Reason", selection: $vm.reason) {
                ForEach(RefundReason.allCases) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .accessibilityLabel("Refund reason picker")
        }
        .cardBackground()
    }

    private var pinConfirmedBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.bizarreSuccess)
            Text("Manager approved").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSuccess.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Manager authorization confirmed")
    }

    private var submitButton: some View {
        Button {
            Task { await vm.submitRefund() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView().tint(.white)
                } else {
                    HStack {
                        if vm.requiresManagerPin {
                            Image(systemName: "lock.shield")
                        }
                        Text(vm.requiresManagerPin ? "Approve & Refund" : "Issue Refund")
                            .font(.brandTitleMedium())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                    tint: .bizarreError,
                    interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || {
            if case .submitting = vm.state { return true }
            return false
        }())
        .accessibilityLabel(vm.requiresManagerPin
            ? "Approve and issue refund — requires manager PIN"
            : "Issue refund")
    }
}

// MARK: - Sheet behavior modifier

private struct SheetBehaviorModifier: ViewModifier {
    let vm: InvoiceRefundViewModel
    let onSuccess: (RefundResult) -> Void
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .onChange(of: vm.state) { _, newState in
                if case let .success(result) = newState {
                    onSuccess(result)
                    dismiss()
                }
            }
            .alert("Refund Error", isPresented: .constant({
                if case .failed = vm.state { return true }
                return false
            }()), actions: {
                Button("OK") { vm.resetToIdle() }
            }, message: {
                if case let .failed(msg) = vm.state { Text(msg) }
            })
    }
}

private extension View {
    func applySheetBehavior(
        vm: InvoiceRefundViewModel,
        onSuccess: @escaping (RefundResult) -> Void,
        dismiss: DismissAction
    ) -> some View {
        modifier(SheetBehaviorModifier(vm: vm, onSuccess: onSuccess, dismiss: dismiss))
    }
}

// MARK: - Manager PIN Sheet

public struct ManagerPinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    let onConfirm: (String) -> Void

    public init(onConfirm: @escaping (String) -> Void) {
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOrange)

                    Text("Manager Authorization Required")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.center)

                    Text("Refunds over $100 require a manager PIN.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)

                    SecureField("Enter PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.brandHeadlineMedium())
                        .multilineTextAlignment(.center)
                        .padding(BrandSpacing.base)
                        .background(Color.bizarreSurface1,
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("Manager PIN field")

                    Button {
                        onConfirm(pin)
                        dismiss()
                    } label: {
                        Text("Authorize")
                            .font(.brandTitleMedium())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BrandSpacing.md)
                    }
                    .brandGlass(.regular,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                                tint: .bizarreOrange,
                                interactive: true)
                    .foregroundStyle(.white)
                    .disabled(pin.isEmpty)
                    .accessibilityLabel("Authorize refund")
                }
                .padding(BrandSpacing.xl)
            }
            .navigationTitle("Manager PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel manager PIN entry")
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Checkbox toggle style

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? .bizarreOrange : .bizarreOnSurfaceMuted)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

private extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkboxStyle: CheckboxToggleStyle { CheckboxToggleStyle() }
}

// MARK: - Helpers

private struct TenderChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(isSelected ? .white : .bizarreOnSurface)
                .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                            in: Capsule())
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: isSelected)
    }
}

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

private func formatCents(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
