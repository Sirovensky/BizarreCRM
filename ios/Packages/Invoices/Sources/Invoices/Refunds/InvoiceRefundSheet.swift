#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.4 Invoice Refund Sheet

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
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        paidSummary
                        amountModeToggle
                        if vm.useLineItems {
                            lineItemsSection
                        } else {
                            manualAmountSection
                        }
                        reasonSection
                        if vm.requiresManagerPin && !vm.managerPin.isEmpty {
                            pinConfirmedBadge
                        }
                        submitButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Issue Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
            .sheet(isPresented: $vm.showManagerPinPrompt) {
                ManagerPinSheet { pin in
                    Task { await vm.submitWithPin(pin) }
                }
            }
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
        .presentationDetents(Platform.isCompact ? [.large] : [.large])
    }

    // MARK: - Sections

    private var paidSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Total Paid").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.totalPaidCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("Refunding").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
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

    private var amountModeToggle: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Refund Mode").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
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
                    .accessibilityLabel("\(item.displayName), \(formatCents(item.totalCents)). \(item.isSelected ? "Selected" : "Not selected").")
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

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
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
        .background(Color.bizarreSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
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
                        if vm.requiresManagerPin { Image(systemName: "lock.shield") }
                        Text(vm.requiresManagerPin ? "Approve & Refund" : "Issue Refund")
                            .font(.brandTitleMedium())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: .bizarreError, interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || {
            if case .submitting = vm.state { return true }
            return false
        }())
        .accessibilityLabel(vm.requiresManagerPin ? "Approve and issue refund — requires manager PIN" : "Issue refund")
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
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
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
                    .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: .bizarreOrange, interactive: true)
                    .foregroundStyle(.white)
                    .disabled(pin.isEmpty)
                }
                .padding(BrandSpacing.xl)
            }
            .navigationTitle("Manager PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
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
