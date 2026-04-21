#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.3 Invoice Payment Sheet
// iPhone: bottom sheet (.presentationDetents). iPad: side panel.

public struct InvoicePaymentSheet: View {
    @State private var vm: InvoicePaymentViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSuccess: (PaymentResult) -> Void

    public init(vm: InvoicePaymentViewModel, onSuccess: @escaping (PaymentResult) -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        balanceSummary
                        tenderSection
                        amountSection
                        if vm.tender != .cash {
                            feeSection
                        }
                        notesSection
                        if vm.isPartialPayment {
                            partialWarning
                        }
                        submitButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
            .onChange(of: vm.state) { _, newState in
                if case let .success(result) = newState {
                    onSuccess(result)
                    dismiss()
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .alert("Payment Error", isPresented: .constant({
            if case .failed = vm.state { return true }
            return false
        }()), actions: {
            Button("OK") { vm.resetToIdle() }
        }, message: {
            if case let .failed(msg) = vm.state { Text(msg) }
        })
    }

    // MARK: - Sections

    private var balanceSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Balance Due").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.balanceCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
            Spacer()
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Balance due: \(formatCents(vm.balanceCents))")
    }

    private var tenderSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payment Method")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(InvoiceTender.allCases) { tender in
                        TenderChip(
                            label: tender.displayName,
                            isSelected: vm.tender == tender
                        ) {
                            vm.tender = tender
                        }
                        .accessibilityLabel("\(tender.displayName) payment method")
                        .accessibilityAddTraits(vm.tender == tender ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }
        }
        .cardBackground()
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Amount")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                Text("$").font(.brandHeadlineMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.amountString)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Payment amount in dollars")
            }

            if let fieldErr = vm.fieldErrors["amount"] {
                Text(fieldErr).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
            }
        }
        .cardBackground()
    }

    private var feeSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Processing Fee (optional)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                Text("$").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: Binding(
                    get: { vm.feeCents == 0 ? "" : String(format: "%.2f", Double(vm.feeCents) / 100.0) },
                    set: { str in
                        if let d = Double(str.filter { $0.isNumber || $0 == "." }) {
                            vm.feeCents = Int((d * 100).rounded())
                        } else {
                            vm.feeCents = 0
                        }
                    }
                ))
                .keyboardType(.decimalPad)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Processing fee in dollars")
            }
        }
        .cardBackground()
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes (optional)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("Reference, check number, etc.", text: $vm.notes, axis: .vertical)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(3...)
                .accessibilityLabel("Payment notes")
        }
        .cardBackground()
    }

    private var partialWarning: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.bizarreWarning)
            Text("Partial payment — invoice will be marked partially paid.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Warning: partial payment. Invoice will be marked partially paid.")
    }

    private var submitButton: some View {
        Button {
            Task { await vm.applyPayment() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView().tint(.white)
                } else {
                    Text("Apply Payment")
                        .font(.brandTitleMedium())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: .bizarreOrange, interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || {
            if case .submitting = vm.state { return true }
            return false
        }())
        .animation(reduceMotion ? .none : .spring(response: DesignTokens.Motion.snappy), value: vm.state.isSubmitting)
        .accessibilityLabel("Apply payment")
    }
}

// MARK: - Supporting views

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

// MARK: - State helpers

private extension InvoicePaymentViewModel.State {
    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }
}

// MARK: - Card background (duplicated from InvoiceDetailView — kept package-private)

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
