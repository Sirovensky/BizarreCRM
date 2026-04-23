#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.3 / §7.4 Invoice Payment Sheet
// iPhone: bottom sheet (.presentationDetents).
// iPad: side panel (.large detent, adaptive width capped at 540pt).
// Supports single-tender and split-tender (multiple legs).

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
                .navigationTitle("Record Payment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: vm.state, perform: handleStateChange)
        .alert("Payment Error", isPresented: failedBinding, actions: {
            Button("OK") { vm.resetToIdle() }
        }, message: {
            if case let .failed(msg) = vm.state { Text(msg) }
        })
    }

    // MARK: - iPad layout (side panel, capped width)

    private var iPadLayout: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Record Payment")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .frame(maxWidth: 540)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChange(of: vm.state, perform: handleStateChange)
        .alert("Payment Error", isPresented: failedBinding, actions: {
            Button("OK") { vm.resetToIdle() }
        }, message: {
            if case let .failed(msg) = vm.state { Text(msg) }
        })
    }

    // MARK: - Shared content

    private var sheetContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    balanceSummary
                    legsSection
                    if vm.legs.count > 1 {
                        splitSummary
                    }
                    if vm.isOverpayment {
                        changeDueCard
                    }
                    notesSection
                    if vm.isPartialPayment {
                        partialWarning
                    }
                    addLegButton
                    submitButton
                }
                .padding(BrandSpacing.base)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.bizarreOrange)
        }
    }

    // MARK: - Balance summary

    private var balanceSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Balance Due")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.balanceCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
            Spacer()
            if vm.legs.count > 1 {
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text("Remaining")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(formatCents(max(0, vm.remainingCents)))
                        .font(.brandTitleLarge())
                        .foregroundStyle(vm.remainingCents <= 0 ? .bizarreSuccess : .bizarreWarning)
                        .monospacedDigit()
                }
            }
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Balance due: \(formatCents(vm.balanceCents))")
    }

    // MARK: - Payment legs

    private var legsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(vm.legs.count > 1 ? "Split Tender" : "Payment")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            ForEach(Array(vm.legs.enumerated()), id: \.element.id) { index, leg in
                LegRow(
                    leg: leg,
                    showRemove: vm.legs.count > 1,
                    onUpdate: { tender, cents, ref in
                        vm.updateLeg(id: leg.id, tender: tender, amountCents: cents, reference: ref)
                    },
                    onRemove: {
                        vm.removeLeg(at: IndexSet(integer: index))
                    }
                )
            }
        }
        .cardBackground()
    }

    // MARK: - Split tender summary

    private var splitSummary: some View {
        HStack {
            Text("Total tendered")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatCents(vm.totalTenderedCents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total tendered: \(formatCents(vm.totalTenderedCents))")
    }

    // MARK: - Change due (cash overpayment)

    private var changeDueCard: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "banknote").foregroundStyle(.bizarreSuccess)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Change Due")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.changeDueCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreSuccess)
                    .monospacedDigit()
            }
            Spacer()
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Change due: \(formatCents(vm.changeDueCents))")
    }

    // MARK: - Notes

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

    // MARK: - Partial warning

    private var partialWarning: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.bizarreWarning)
            Text("Partial payment — invoice will be marked partially paid.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreWarning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Warning: partial payment. Invoice will be marked partially paid.")
    }

    // MARK: - Add leg button

    private var addLegButton: some View {
        Button {
            vm.addLeg()
        } label: {
            Label("Add Another Method", systemImage: "plus.circle")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOrange)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add another payment method for split tender")
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await vm.applyPayment() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView().tint(.white)
                } else {
                    Text(vm.legs.count > 1 ? "Apply Split Payment" : "Apply Payment")
                        .font(.brandTitleMedium())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                    tint: .bizarreOrange,
                    interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || vm.state.isSubmitting)
        .animation(reduceMotion ? .none : .spring(response: DesignTokens.Motion.snappy),
                   value: vm.state.isSubmitting)
        .accessibilityLabel(vm.legs.count > 1 ? "Apply split payment" : "Apply payment")
    }

    // MARK: - Helpers

    private func handleStateChange(_: InvoicePaymentViewModel.State, _ newState: InvoicePaymentViewModel.State) {
        if case let .success(result) = newState {
            onSuccess(result)
            dismiss()
        }
    }

    private var failedBinding: Binding<Bool> {
        .constant({
            if case .failed = vm.state { return true }
            return false
        }())
    }
}

// MARK: - Leg row

private struct LegRow: View {
    let leg: PaymentLeg
    let showRemove: Bool
    let onUpdate: (InvoiceTender, Int, String) -> Void
    let onRemove: () -> Void

    @State private var amountStr: String = ""
    @State private var ref: String = ""
    @State private var selectedTender: InvoiceTender

    init(leg: PaymentLeg, showRemove: Bool,
         onUpdate: @escaping (InvoiceTender, Int, String) -> Void,
         onRemove: @escaping () -> Void) {
        self.leg = leg
        self.showRemove = showRemove
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        _amountStr = State(initialValue: String(format: "%.2f", Double(leg.amountCents) / 100.0))
        _ref = State(initialValue: leg.reference)
        _selectedTender = State(initialValue: leg.tender)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(InvoiceTender.allCases) { t in
                            TenderChip(label: t.displayName, isSelected: selectedTender == t) {
                                selectedTender = t
                                commitUpdate()
                            }
                            .accessibilityLabel("\(t.displayName) payment method")
                            .accessibilityAddTraits(selectedTender == t ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, BrandSpacing.xxs)
                }

                if showRemove {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.bizarreError)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this payment leg")
                }
            }

            HStack {
                Text("$").font(.brandHeadlineMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $amountStr)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .onChange(of: amountStr) { commitUpdate() }
                    .accessibilityLabel("Payment amount in dollars")
            }

            if selectedTender.needsReference {
                TextField("Reference / last 4", text: $ref)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .onChange(of: ref) { commitUpdate() }
                    .accessibilityLabel("Transaction reference or last four digits")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
    }

    private func commitUpdate() {
        let cents: Int
        if let d = Double(amountStr.filter { $0.isNumber || $0 == "." }) {
            cents = Int((d * 100).rounded())
        } else {
            cents = leg.amountCents
        }
        onUpdate(selectedTender, cents, ref)
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

extension InvoicePaymentViewModel.State {
    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }
}

// MARK: - Card background

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
