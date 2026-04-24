#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Bottom CTA row for the tender flow.
///
/// Shows three actions:
/// 1. "Split payment" — enabled when `remaining > 0` and at least one tender
///    leg has been applied (i.e. mid-flow return to method picker).
/// 2. "Add tip" — opens the tip-entry popover.
/// 3. "Confirm" — enabled when `remaining == 0`. Triggers coordinator.confirm().
///
/// Haptic `.sensoryFeedback(.success)` fires when `coordinator.stage` becomes
/// `.confirmed`.
public struct PosTenderAmountBar: View {

    @Bindable public var coordinator: PosTenderCoordinator

    @State private var showTipEntry: Bool = false
    @State private var tipDollarsInput: String = ""
    @State private var confirmedAt: Date? = nil

    @Environment(\.posTheme) private var theme

    public init(coordinator: PosTenderCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(theme.outline)
            buttonRow
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.lg)
                .background(.ultraThinMaterial)
        }
        .sensoryFeedback(.success, trigger: confirmedAt)
        .onChange(of: coordinator.stage) { _, newStage in
            if newStage == .confirmed {
                confirmedAt = Date()
            }
        }
        .sheet(isPresented: $showTipEntry) {
            tipEntrySheet
        }
        .alert("Payment error", isPresented: Binding(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.clearError() } }
        )) {
            Button("OK") { coordinator.clearError() }
        } message: {
            if let msg = coordinator.errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Button row

    private var buttonRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Split payment
            Button {
                // Already tracked by coordinator.isSplit.
                // If user taps "Split" from the amount-entry stage, cancel
                // current amount entry and return to method picker.
                coordinator.cancelAmountEntry()
            } label: {
                Label("Split", systemImage: "creditcard.and.123")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.on)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(theme.surfaceElev, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(coordinator.appliedTenders.isEmpty)
            .opacity(coordinator.appliedTenders.isEmpty ? 0.4 : 1.0)
            .accessibilityLabel("Split payment")
            .accessibilityHint("Add another payment method to cover the remaining balance")
            .accessibilityIdentifier("pos.tenderBar.split")

            // Add tip
            Button {
                showTipEntry = true
            } label: {
                Label("Tip", systemImage: "plus.circle")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.on)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(theme.surfaceElev, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(coordinator.tipCents > 0
                ? "Tip: \(CartMath.formatCents(coordinator.tipCents))"
                : "Add tip")
            .accessibilityHint("Add a tip to the transaction")
            .accessibilityIdentifier("pos.tenderBar.tip")

            Spacer()

            // Confirm
            Button {
                Task { await coordinator.confirm() }
            } label: {
                Group {
                    if coordinator.isConfirming {
                        ProgressView()
                            .tint(theme.onPrimary)
                            .controlSize(.small)
                    } else {
                        Text("Confirm")
                            .font(.brandTitleMedium())
                    }
                }
                .frame(minWidth: 100)
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(confirmEnabled ? theme.onPrimary : theme.muted)
            }
            .buttonStyle(.borderedProminent)
            .tint(confirmEnabled ? theme.primary : theme.surfaceElev)
            .disabled(!confirmEnabled)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Confirm payment")
            .accessibilityHint(coordinator.remaining == 0
                ? "Finalize the transaction"
                : "Enter full payment before confirming")
            .accessibilityIdentifier("pos.tenderBar.confirm")
        }
    }

    private var confirmEnabled: Bool {
        coordinator.remaining == 0 &&
        !coordinator.appliedTenders.isEmpty &&
        !coordinator.isConfirming
    }

    // MARK: - Tip entry sheet

    private var tipEntrySheet: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.xl) {
                VStack(spacing: BrandSpacing.xxs) {
                    Text("Add tip")
                        .font(.brandTitleLarge())
                        .foregroundStyle(theme.on)
                    Text("Applied to the transaction total")
                        .font(.brandBodyMedium())
                        .foregroundStyle(theme.muted)
                }
                .padding(.top, BrandSpacing.lg)

                // Preset amounts
                HStack(spacing: BrandSpacing.sm) {
                    tipPreset(label: "10%", cents: Int(Double(coordinator.totalCents) * 0.10))
                    tipPreset(label: "15%", cents: Int(Double(coordinator.totalCents) * 0.15))
                    tipPreset(label: "20%", cents: Int(Double(coordinator.totalCents) * 0.20))
                }
                .padding(.horizontal, BrandSpacing.base)

                // Custom input
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Custom amount")
                        .font(.brandLabelLarge())
                        .foregroundStyle(theme.muted)
                    TextField("0.00", text: $tipDollarsInput)
                        .font(.brandHeadlineMedium())
                        .keyboardType(.decimalPad)
                        .padding(BrandSpacing.md)
                        .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(theme.outline, lineWidth: 0.5)
                        )
                        .accessibilityIdentifier("pos.tenderBar.tipField")
                }
                .padding(.horizontal, BrandSpacing.base)

                Spacer()
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTipEntry = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyTip()
                        showTipEntry = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func tipPreset(label: String, cents: Int) -> some View {
        Button {
            coordinator.setTip(cents: cents)
            tipDollarsInput = String(format: "%.2f", Double(cents) / 100.0)
        } label: {
            VStack(spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandTitleSmall())
                    .foregroundStyle(theme.on)
                Text(CartMath.formatCents(cents))
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .background(coordinator.tipCents == cents ? theme.primarySoft : theme.surfaceElev,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        coordinator.tipCents == cents ? theme.primary : theme.outline,
                        lineWidth: coordinator.tipCents == cents ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) tip: \(CartMath.formatCents(cents))")
        .accessibilityIdentifier("pos.tenderBar.tipPreset.\(label)")
    }

    private func applyTip() {
        let cleaned = tipDollarsInput
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleaned), dollars >= 0 else { return }
        let cents = Int((dollars * 100).rounded())
        coordinator.setTip(cents: cents)
    }
}
#endif
