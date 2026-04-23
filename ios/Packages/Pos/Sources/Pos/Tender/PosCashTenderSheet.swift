#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.6 — Cash tender entry sheet.
///
/// Presents a currency text field with quick-amount chips ("Exact", "$20",
/// "$50", etc.) and a large "Change due" card once the entered amount
/// covers the total.
///
/// On tap of the Charge button:
///   1. `CashTenderViewModel.charge()` posts to `POST /pos/transaction`.
///   2. On success: calls `onCompleted` with the `CashTenderResult`.
///   3. On failure: shows an inline error banner.
///
/// Caller dismisses this sheet from `onCompleted`.
struct PosCashTenderSheet: View {
    @Bindable var vm: CashTenderViewModel
    let onCompleted: (CashTenderResult) -> Void
    let onBack: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                switch vm.phase {
                case .entry:
                    entryContent
                case .processing:
                    processingContent
                case .changeDue(let result):
                    changeDueContent(result: result)
                case .failed(let msg):
                    failedContent(message: msg)
                }
            }
            .navigationTitle("Cash payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onBack() }
                        .disabled(vm.phase == .processing)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Entry content

    private var entryContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                totalDueRow
                amountReceivedField
                quickAmountChips
                changeDuePreview
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            chargeButton
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
                .background(Color.bizarreSurfaceBase.opacity(0.97))
        }
    }

    private var totalDueRow: some View {
        HStack {
            Text("Total due")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(vm.totalCents))
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                        }
    }

    private var amountReceivedField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Amount received")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                Text("$")
                    .font(.brandHeadlineLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: Binding(
                    get: { vm.rawInput },
                    set: { vm.updateInput($0) }
                ))
                .keyboardType(.decimalPad)
                .font(.brandHeadlineLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.cash.amountField")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        vm.canCharge ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOutline.opacity(0.5),
                        lineWidth: 0.75
                    )
            )
        }
    }

    private var quickAmountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                quickChip(label: "Exact") { vm.setExact() }
                if vm.totalCents <= 500 {
                    quickChip(label: "$5") { vm.setRounded(to: 5) }
                }
                if vm.totalCents <= 1000 {
                    quickChip(label: "$10") { vm.setRounded(to: 10) }
                }
                quickChip(label: "$20") { vm.setRounded(to: 20) }
                if vm.totalCents > 2000 {
                    quickChip(label: "$50") { vm.setRounded(to: 50) }
                }
                if vm.totalCents > 5000 {
                    quickChip(label: "$100") { vm.setRounded(to: 100) }
                }
            }
        }
    }

    private func quickChip(label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.brandLabelLarge())
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .background(Color.bizarreSurface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
            .foregroundStyle(.bizarreOnSurface)
            .buttonStyle(.plain)
            .accessibilityLabel("Set amount to \(label)")
    }

    /// Shows "Change: $X.XX" only when the entered amount exceeds the total.
    @ViewBuilder
    private var changeDuePreview: some View {
        if let change = vm.changeCents, change > 0 {
            HStack {
                Text("Change due")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(change))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .monospacedDigit()
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreSuccess.opacity(0.3), lineWidth: 0.5)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityIdentifier("pos.cash.changePreview")
        }
    }

    private var chargeButton: some View {
        Button {
            Task { await vm.charge() }
        } label: {
            Label("Charge \(CartMath.formatCents(vm.totalCents))", systemImage: "banknote")
                .font(.brandTitleMedium())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!vm.canCharge)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityIdentifier("pos.cash.chargeButton")
    }

    // MARK: - Processing

    private var processingContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(.bizarreOrange)
            Text("Processing…")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pos.cash.processing")
    }

    // MARK: - Change due (success) screen

    private func changeDueContent(result: CashTenderResult) -> some View {
        VStack(spacing: 0) {
            Spacer()
            // Large change-due glass card — the primary visual anchor for the
            // cashier handing back money to the customer.
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)

                if result.changeCents > 0 {
                    VStack(spacing: BrandSpacing.xs) {
                        Text("Change due")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(CartMath.formatCents(result.changeCents))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.bizarreSuccess)
                            .monospacedDigit()
                                                        .accessibilityIdentifier("pos.cash.changeDue")
                    }
                } else {
                    Text("Exact amount — no change")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityIdentifier("pos.cash.exactAmount")
                }

                VStack(spacing: BrandSpacing.xs) {
                    Text("Charged \(CartMath.formatCents(result.totalCents))")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                    if let orderId = result.orderId {
                        Text("Order \(orderId)")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xxl)
            .padding(.horizontal, BrandSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, BrandSpacing.base)
            .accessibilityIdentifier("pos.cash.successCard")

            Spacer()

            Button {
                onCompleted(result)
            } label: {
                Label("Continue", systemImage: "arrow.forward.circle.fill")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("pos.cash.continueButton")
        }
        .accessibilityIdentifier("pos.cash.completed")
    }

    // MARK: - Error

    private func failedContent(message: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(spacing: BrandSpacing.sm) {
                Text("Transaction failed")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                    .accessibilityIdentifier("pos.cash.errorMessage")
            }
            Button("Try again") {
                vm.resetToEntry()
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("pos.cash.tryAgain")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pos.cash.failed")
    }
}

#Preview("Cash entry") {
    let vm = CashTenderViewModel(
        totalCents: 4275,
        transactionRequest: PosTransactionRequest(
            items: [],
            idempotencyKey: UUID().uuidString
        )
    )
    return PosCashTenderSheet(vm: vm, onCompleted: { _ in }, onBack: {})
        .preferredColorScheme(.dark)
}
#endif
