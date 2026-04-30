#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.7 Customer return flow — Invoice detail → "Return items" → pick lines + qty
//      + per-item disposition (salable / scrap / damaged)
//      + fraud guard (warn on high-$, manager PIN required above threshold)
//      + restocking fee preview
//      + tender selection (non-BlockChyp: cash / store credit / gift card)
//
// iPhone: .large sheet.
// iPad: 560pt wide modal.

public struct InvoiceReturnSheet: View {
    @State private var vm: InvoiceReturnViewModel
    @Environment(\.dismiss) private var dismiss

    let onSuccess: (Int64) -> Void

    public init(vm: InvoiceReturnViewModel, onSuccess: @escaping (Int64) -> Void) {
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

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Return Items")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .applyReturnSheetBehavior(vm: vm, onSuccess: onSuccess, dismiss: dismiss)
    }

    private var iPadLayout: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Return Items")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { cancelButton }
                .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .frame(maxWidth: 560)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .applyReturnSheetBehavior(vm: vm, onSuccess: onSuccess, dismiss: dismiss)
    }

    // MARK: - Content

    private var sheetContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    if vm.lines.isEmpty {
                        emptyLinesState
                    } else {
                        lineItemsSection
                        if !vm.selectedLines.isEmpty {
                            restockingFeeCard
                            tenderSection
                            reasonSection
                            fraudWarningCard
                            submitButton
                        }
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
        // Fraud warning alert
        .alert("High-Value Return", isPresented: $vm.showFraudWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Continue — Requires Manager PIN") {
                vm.acknowledgeFraudWarning()
            }
        } message: {
            Text("This return exceeds $\(kReturnManagerPinThresholdCents / 100). A manager PIN is required to proceed.")
        }
        // Manager PIN sheet
        .sheet(isPresented: $vm.showManagerPinPrompt) {
            ReturnManagerPinSheet { pin in
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

    private var emptyLinesState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No returnable line items found.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, BrandSpacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No returnable line items.")
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Select Items to Return")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            ForEach($vm.lines) { $line in
                ReturnLineRow(line: $line)
                    .hoverEffect(.highlight)
            }
        }
        .cardBackground()
    }

    @ViewBuilder
    private var restockingFeeCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Gross Refund")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(formatCents(vm.grossRefundCents))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                Spacer()
                if vm.totalRestockingFeeCents > 0 {
                    VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                        Text("Restocking Fee")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                        Text("− \(formatCents(vm.totalRestockingFeeCents))")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .monospacedDigit()
                    }
                }
            }
            Divider()
            HStack {
                Text("Net Refund")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatCents(vm.netRefundCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(vm.exceedsFraudThreshold ? .bizarreWarning : .bizarreSuccess)
                    .monospacedDigit()
            }
            if vm.exceedsFraudThreshold {
                Label("Manager PIN required above $\(kReturnManagerPinThresholdCents / 100)", systemImage: "lock.shield")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
            }
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Gross refund \(formatCents(vm.grossRefundCents)). " +
            (vm.totalRestockingFeeCents > 0 ? "Restocking fee \(formatCents(vm.totalRestockingFeeCents)). " : "") +
            "Net refund \(formatCents(vm.netRefundCents))."
        )
    }

    private var tenderSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Refund Method")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(ReturnTender.allCases) { tender in
                        ReturnTenderChip(
                            tender: tender,
                            isSelected: vm.selectedTender == tender
                        ) {
                            vm.selectedTender = tender
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }
        }
        .cardBackground()
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Return Reason")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("Describe the reason for the return…", text: $vm.returnReason, axis: .vertical)
                .lineLimit(3...6)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .accessibilityLabel("Return reason text field")
            if let err = vm.fieldErrors["reason"] {
                Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
            }
        }
        .cardBackground()
    }

    @ViewBuilder
    private var fraudWarningCard: some View {
        if vm.exceedsFraudThreshold {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreWarning)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("High-value return")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Manager authorization required above $\(kReturnManagerPinThresholdCents / 100).")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreWarning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("High-value return. Manager authorization required.")
        }
    }

    private var submitButton: some View {
        Button {
            Task { await vm.submitReturn() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: BrandSpacing.sm) {
                        if vm.requiresManagerPin {
                            Image(systemName: "lock.shield")
                        }
                        Text(vm.requiresManagerPin ? "Authorize & Process Return" : "Process Return")
                            .font(.brandTitleMedium())
                    }
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
        .disabled(!vm.isValid || {
            if case .submitting = vm.state { return true }
            return false
        }())
        .accessibilityLabel(vm.requiresManagerPin
            ? "Authorize and process return — requires manager PIN"
            : "Process return")
    }
}

// MARK: - Return line row

private struct ReturnLineRow: View {
    @Binding var line: InvoiceReturnLine

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Select + title
            HStack(spacing: BrandSpacing.sm) {
                Button {
                    line.isSelected.toggle()
                } label: {
                    Image(systemName: line.isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(line.isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(line.isSelected ? "Deselect \(line.displayName)" : "Select \(line.displayName)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(line.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let sku = line.sku {
                        Text(sku)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Text(formatCents(line.grossRefundCents))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            if line.isSelected {
                // Qty stepper
                HStack {
                    Text("Qty:")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Stepper(
                        value: $line.qtyToReturn,
                        in: 1...line.originalQty
                    ) {
                        Text("\(line.qtyToReturn) of \(line.originalQty)")
                            .font(.brandBodyMedium())
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Quantity to return: \(line.qtyToReturn) of \(line.originalQty)")
                }

                // Disposition picker
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Disposition")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Picker("Disposition", selection: $line.disposition) {
                        ForEach(RestockDisposition.allCases) { d in
                            Label(d.displayName, systemImage: d.systemImage).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Item disposition picker")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: line.isSelected)
    }
}

// MARK: - Tender chip

private struct ReturnTenderChip: View {
    let tender: ReturnTender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tender.displayName, systemImage: tender.systemImage)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(isSelected ? .white : .bizarreOnSurface)
                .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                            in: Capsule())
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: isSelected)
        .accessibilityLabel("\(tender.displayName) refund method")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Manager PIN sheet for returns

private struct ReturnManagerPinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    let onConfirm: (String) -> Void

    var body: some View {
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

                    Text("Returns over $\(kReturnManagerPinThresholdCents / 100) require a manager PIN.")
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
                        .accessibilityLabel("Manager PIN entry field")

                    Button {
                        onConfirm(pin)
                        dismiss()
                    } label: {
                        Text("Authorize Return")
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
                    .accessibilityLabel("Authorize return with manager PIN")
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

// MARK: - Sheet behavior modifier

private struct ReturnSheetBehaviorModifier: ViewModifier {
    let vm: InvoiceReturnViewModel
    let onSuccess: (Int64) -> Void
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .onChange(of: vm.state) { _, newState in
                if case let .success(refundId) = newState {
                    onSuccess(refundId)
                    dismiss()
                }
            }
            .alert("Return Error", isPresented: .constant({
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
    func applyReturnSheetBehavior(
        vm: InvoiceReturnViewModel,
        onSuccess: @escaping (Int64) -> Void,
        dismiss: DismissAction
    ) -> some View {
        modifier(ReturnSheetBehaviorModifier(vm: vm, onSuccess: onSuccess, dismiss: dismiss))
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
