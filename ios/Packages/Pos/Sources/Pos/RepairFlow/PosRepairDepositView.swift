#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairDepositView (Frame 1e)
//
// Step 4: Collect deposit before work begins.
//
// Imports the tender UI from `RepairDepositCoordinator` (stub until Agent D
// lands). Shows "Deposit $X of $Y" header and "Balance due at pickup" footer.
//
// Server wiring: after deposit is confirmed the parent coordinator calls
// POST /api/v1/tickets/:id/convert-to-invoice.

public struct PosRepairDepositView: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    @State private var depositCoordinator: RepairDepositCoordinator

    public init(coordinator: PosRepairFlowCoordinator) {
        self.coordinator = coordinator
        // Seed with the coordinator's current draft deposit.
        let total = coordinator.draft.estimateCents
        let deposit = coordinator.draft.depositCents > 0
            ? coordinator.draft.depositCents
            : coordinator.draft.suggestedDepositCents
        self._depositCoordinator = State(
            wrappedValue: RepairDepositCoordinator(totalCents: total, defaultDepositCents: deposit)
        )
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                progressHeader

                depositHeaderCard

                amountEditor

                tenderSummarySection

                balanceFooter
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle(RepairStep.deposit.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    coordinator.goBack()
                }
                .accessibilityLabel("Back to diagnostic quote")
                .accessibilityIdentifier("repairFlow.deposit.back")
            }
        }
        .onChange(of: depositCoordinator.depositCents) { _, newValue in
            coordinator.setDepositCents(newValue)
        }
    }

    // MARK: - Sub-views

    private var progressHeader: some View {
        ProgressView(value: RepairStep.deposit.progressPercent, total: 100)
            .progressViewStyle(.linear)
            .tint(.bizarreOrange)
            .padding(.top, BrandSpacing.md)
            .accessibilityLabel(RepairStep.deposit.accessibilityDescription)
            .accessibilityValue("100%")
    }

    private var depositHeaderCard: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text(depositCoordinator.depositHeaderText)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("repairFlow.deposit.header")

            Text("15% deposit collected before work begins")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1))
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var amountEditor: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Deposit amount")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            // Quick amount chips.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    let total = depositCoordinator.totalCents
                    ForEach([10, 15, 20, 25, 50], id: \.self) { pct in
                        let cents = Int((Double(total) * Double(pct) / 100).rounded())
                        Button {
                            depositCoordinator.depositCents = cents
                            BrandHaptics.tap()
                        } label: {
                            Text("\(pct)%")
                                .font(.brandLabelLarge())
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(
                                    depositCoordinator.depositCents == cents
                                        ? Color.bizarreOrange
                                        : Color.bizarreSurface2,
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    depositCoordinator.depositCents == cents
                                        ? Color.white
                                        : Color.bizarreOnSurface
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pct)% deposit: \(RepairDepositCoordinator.formatCurrency(cents: cents))")
                        .accessibilityIdentifier("repairFlow.deposit.pct\(pct)")
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }

            // Custom amount numpad field.
            HStack {
                Text("$")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                TextField(
                    "0.00",
                    value: Binding(
                        get: { Double(depositCoordinator.depositCents) / 100.0 },
                        set: { depositCoordinator.depositCents = Int(($0 * 100).rounded()) }
                    ),
                    format: .number.precision(.fractionLength(2))
                )
                .keyboardType(.decimalPad)
                .font(.brandTitleLarge().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Custom deposit amount in dollars")
                .accessibilityIdentifier("repairFlow.deposit.customAmount")
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOrange.opacity(0.6), lineWidth: 1))
        }
    }

    private var tenderSummarySection: some View {
        // TODO: Replace with PosTenderCoordinator UI once Agent D lands.
        // For now, display a placeholder that mirrors the expected tender shape.
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payment method")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            HStack(spacing: BrandSpacing.md) {
                ForEach(["Cash", "Card", "Gift card"], id: \.self) { method in
                    Button {
                        // TODO: wire to PosTenderCoordinator.selectMethod(_:)
                        AppLog.pos.info("RepairFlow deposit: tender method tapped: \(method, privacy: .public)")
                    } label: {
                        VStack(spacing: BrandSpacing.xxs) {
                            Image(systemName: methodIcon(method))
                                .font(.title2)
                                .foregroundStyle(.bizarreOrange)
                            Text(method)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(BrandSpacing.sm)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(method) payment")
                    .accessibilityIdentifier("repairFlow.deposit.tenderMethod.\(method)")
                }
            }

            Text("Full tender integration available after Agent D PosTenderCoordinator merges.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.top, BrandSpacing.xxs)
        }
    }

    private var balanceFooter: some View {
        HStack {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(depositCoordinator.balanceFooterText)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(depositCoordinator.balanceFooterText)
        .accessibilityIdentifier("repairFlow.deposit.balanceFooter")
    }

    // MARK: - CTA bar

    private var ctaBar: some View {
        VStack(spacing: BrandSpacing.xs) {
            if let error = coordinator.errorMessage ?? depositCoordinator.errorMessage {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.md)
            }

            Button {
                depositCoordinator.onTendered = { cents in
                    coordinator.setDepositCents(cents)
                    coordinator.advance()
                }
                depositCoordinator.confirmDeposit()
                BrandHaptics.tapMedium()
            } label: {
                HStack {
                    if coordinator.isLoading || depositCoordinator.isProcessing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Collect deposit")
                            .font(.brandTitleSmall())
                        Image(systemName: "checkmark")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(coordinator.isLoading || depositCoordinator.isProcessing || depositCoordinator.depositCents <= 0)
            .sensoryFeedback(.success, trigger: coordinator.isComplete)
            .accessibilityLabel("Collect deposit and create invoice")
            .accessibilityHint("Finalises the repair ticket and converts it to an invoice")
            .accessibilityIdentifier("repairFlow.deposit.collect")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func methodIcon(_ method: String) -> String {
        switch method {
        case "Cash":      return "banknote"
        case "Card":      return "creditcard"
        case "Gift card": return "giftcard"
        default:          return "dollarsign.circle"
        }
    }
}
#endif
