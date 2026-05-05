#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.5 — Cash tender entry and change-due sheet.
///
/// Phase machine:
/// - `.entry`:      Amount-received input + quick-chips + live change preview.
/// - `.processing`: Spinner while posting to `/pos/transaction`.
/// - `.changeDue`:  Success card — invoice confirmed, change due.
/// - `.failed`:     Error card with retry.
///
/// Glass is used only on the navigation chrome (toolbar), not on the
/// content rows or the success card itself (per CLAUDE.md).
public struct PosCashTenderSheet: View {
    @Bindable public var vm: CashTenderViewModel
    public let onCompleted: (CashTenderResult) -> Void
    public let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFieldFocused: Bool

    public init(
        vm: CashTenderViewModel,
        onCompleted: @escaping (CashTenderResult) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.vm = vm
        self.onCompleted = onCompleted
        self.onBack = onBack
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Cash payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                        onBack()
                    }
                    .disabled(vm.phase == .processing)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
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

    // MARK: - Entry phase

    private var entryContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    totalDueHeader
                        .padding(.top, BrandSpacing.xl)

                    amountField
                        .padding(.horizontal, BrandSpacing.base)

                    quickChips
                        .padding(.horizontal, BrandSpacing.base)

                    if vm.receivedCents >= vm.totalCents {
                        changePreview
                            .padding(.horizontal, BrandSpacing.base)
                    }
                }
            }

            chargeButton
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.lg)
                .padding(.top, BrandSpacing.sm)
        }
        .onAppear { amountFieldFocused = true }
    }

    private var totalDueHeader: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("Total due")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(CartMath.formatCents(vm.totalCents))
                .font(.brandHeadlineLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.cashTender.total")
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Amount received")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("0.00", text: $vm.rawInput)
                .font(.brandHeadlineMedium())
                .monospacedDigit()
                .keyboardType(.decimalPad)
                .focused($amountFieldFocused)
                .onChange(of: vm.rawInput) { _, new in vm.updateInput(new) }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.bizarreOutline, lineWidth: 0.5)
                )
                .accessibilityIdentifier("pos.cashTender.amountField")
        }
    }

    private var quickChips: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Quick amounts")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    quickChip(label: "Exact") { vm.setExact() }
                    quickChip(label: "$5")   { vm.setRounded(to: 500) }
                    quickChip(label: "$10")  { vm.setRounded(to: 1000) }
                    quickChip(label: "$20")  { vm.setRounded(to: 2000) }
                    quickChip(label: "$50")  { vm.setRounded(to: 5000) }
                    quickChip(label: "$100") { vm.setRounded(to: 10000) }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func quickChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOutline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("pos.cashTender.quick.\(label)")
    }

    private var changePreview: some View {
        HStack {
            Text("Change due")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(vm.changeFormatted)
                .font(.brandBodyLarge())
                .foregroundStyle(vm.changeCents > 0 ? .bizarreOrange : .bizarreOnSurface)
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("pos.cashTender.changePreview")
    }

    private var chargeButton: some View {
        Button {
            amountFieldFocused = false
            Task { await vm.charge() }
        } label: {
            Text("Charge \(CartMath.formatCents(vm.totalCents))")
                .font(.brandTitleMedium())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(vm.canCharge ? .black : .bizarreOnSurfaceMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(vm.canCharge ? .bizarreOrange : Color.bizarreSurface1)
        .disabled(!vm.canCharge)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityIdentifier("pos.cashTender.chargeButton")
    }

    // MARK: - Processing phase

    private var processingContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(.bizarreOrange)
            Text("Processing payment…")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pos.cashTender.processing")
    }

    // MARK: - Change due phase

    private func changeDueContent(result: CashTenderResult) -> some View {
        VStack(spacing: 0) {
            Spacer()
            changeDueCard(result: result)
                .padding(.horizontal, BrandSpacing.base)
            Spacer()
            Button {
                dismiss()
                onCompleted(result)
            } label: {
                Text("Continue")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("pos.cashTender.continueButton")
        }
    }

    private func changeDueCard(result: CashTenderResult) -> some View {
        VStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
            }
            .accessibilityHidden(true)

            Text(CartMath.formatCents(result.totalCents) + " charged")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.cashTender.chargedAmount")

            if result.changeCents > 0 {
                VStack(spacing: BrandSpacing.xxs) {
                    Text("Change due")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(result.changeCents))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                        .accessibilityIdentifier("pos.cashTender.change")
                }
            } else {
                Text("No change due")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let orderId = result.orderId {
                Text("Order \(orderId)")
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("pos.cashTender.orderId")
            }
        }
        .padding(.vertical, BrandSpacing.xl)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Failed phase

    private func failedContent(message: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)

                Text("Payment failed")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.sm)
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, BrandSpacing.base)

            Spacer()

            Button {
                vm.resetToEntry()
            } label: {
                Text("Try again")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .accessibilityIdentifier("pos.cashTender.retryButton")
        }
        .accessibilityIdentifier("pos.cashTender.failed")
    }
}
#endif
