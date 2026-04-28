#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - Denomination model

/// §39 (Discovered from §14) — US-dollar denominations for drawer count.
public struct Denomination: Identifiable, Sendable, Equatable {
    public let id: Int     // face value in cents
    public let label: String
    public let symbol: String  // SF Symbol
    public var count: Int = 0

    public var subtotalCents: Int { id * count }

    public static let all: [Denomination] = [
        Denomination(id: 10_000, label: "$100", symbol: "banknote"),
        Denomination(id:  5_000, label: "$50",  symbol: "banknote"),
        Denomination(id:  2_000, label: "$20",  symbol: "banknote"),
        Denomination(id:  1_000, label: "$10",  symbol: "banknote"),
        Denomination(id:    500, label: "$5",   symbol: "banknote"),
        Denomination(id:    100, label: "$1",   symbol: "banknote"),
        Denomination(id:     25, label: "25¢",  symbol: "circle"),
        Denomination(id:     10, label: "10¢",  symbol: "circle"),
        Denomination(id:      5, label: "5¢",   symbol: "circle"),
        Denomination(id:      1, label: "1¢",   symbol: "circle"),
    ]
}

// MARK: - DenominationCountViewModel

/// §39 — Drive denomination cash-count sheet.
///
/// Cashier enters count-per-denomination; VM computes total and live delta
/// vs `expectedCents`.  Over-short reason is required when
/// `abs(varianceCents) > CashVariance.amberCeilingCents`.
///
/// Sovereignty: all data stays on the tenant server (`APIClient.baseURL`).
@MainActor
@Observable
public final class DenominationCountViewModel {

    // MARK: - State

    public var denominations: [Denomination] = Denomination.all
    public var overShortReason: String = ""
    public var managerPinApproved: Bool = false

    public let expectedCents: Int

    public init(expectedCents: Int) {
        self.expectedCents = expectedCents
    }

    // MARK: - Derived

    public var totalCountedCents: Int {
        denominations.reduce(0) { $0 + $1.subtotalCents }
    }

    public var varianceCents: Int { totalCountedCents - expectedCents }
    public var varianceBand: CashVariance.Band { CashVariance.band(cents: varianceCents) }

    public var requiresManagerPin: Bool {
        varianceBand == .red
    }

    public var requiresReason: Bool {
        CashVariance.notesRequired(cents: varianceCents)
    }

    /// True when the cashier can proceed to the sign-off step.
    public var canProceed: Bool {
        let reasonOK = requiresReason
            ? !overShortReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : true
        let pinOK = requiresManagerPin ? managerPinApproved : true
        return reasonOK && pinOK
    }

    // MARK: - Mutators

    public func increment(_ denomination: Denomination) {
        guard let idx = denominations.firstIndex(where: { $0.id == denomination.id }) else { return }
        denominations[idx].count += 1
    }

    public func decrement(_ denomination: Denomination) {
        guard let idx = denominations.firstIndex(where: { $0.id == denomination.id }) else { return }
        if denominations[idx].count > 0 { denominations[idx].count -= 1 }
    }

    public func setCount(_ count: Int, for denomination: Denomination) {
        guard let idx = denominations.firstIndex(where: { $0.id == denomination.id }) else { return }
        denominations[idx].count = max(0, count)
    }

    public func reset() {
        denominations = Denomination.all
        overShortReason = ""
        managerPinApproved = false
    }
}

// MARK: - DenominationCountView

/// §39 (Discovered §14) — Denomination cash-count sheet.
///
/// Shows a stepper for each denomination; live total + variance vs expected
/// updates in real time. Over $5 variance requires reason + manager PIN.
///
/// iPhone: scrollable form sheet.
/// iPad: same (the sheet is presented at `.large` detent).
@MainActor
public struct DenominationCountView: View {

    @Bindable var vm: DenominationCountViewModel
    public var onComplete: ((Int, String?) -> Void)?  // (countedCents, overShortReason?)

    @State private var showManagerPin: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        vm: DenominationCountViewModel,
        onComplete: ((Int, String?) -> Void)? = nil
    ) {
        self.vm = vm
        self.onComplete = onComplete
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                // Header: expected vs running total
                headerCard
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.lg)

                // Denomination rows
                VStack(spacing: 0) {
                    ForEach($vm.denominations) { $denom in
                        denominationRow($denom)
                        Divider()
                            .padding(.leading, BrandSpacing.base + 40)
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .padding(.horizontal, BrandSpacing.base)

                // Over-short reason
                if vm.requiresReason {
                    reasonField
                        .padding(.horizontal, BrandSpacing.base)
                }

                // Manager PIN gate status
                if vm.requiresManagerPin {
                    managerPinBanner
                        .padding(.horizontal, BrandSpacing.base)
                }

                // CTA
                Button {
                    onComplete?(vm.totalCountedCents,
                                vm.overShortReason.isEmpty ? nil : vm.overShortReason)
                } label: {
                    Label(
                        "Confirm count — \(CartMath.formatCents(vm.totalCountedCents))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(!vm.canProceed)
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityIdentifier("denomCount.confirm")

                Spacer().frame(height: BrandSpacing.xxl)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Variance \(CartMath.formatCents(abs(vm.varianceCents))) over threshold — manager approval required",
                onApproved: { _ in
                    vm.managerPinApproved = true
                    showManagerPin = false
                    AppLog.pos.info("Denomination count: manager PIN approved for variance=\(vm.varianceCents)c")
                },
                onCancelled: { showManagerPin = false }
            )
        }
        .onChange(of: vm.requiresManagerPin) { _, needed in
            if needed && !vm.managerPinApproved { showManagerPin = true }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack {
            // Expected
            VStack(alignment: .leading, spacing: 4) {
                Text("EXPECTED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .tracking(1)
                Text(CartMath.formatCents(vm.expectedCents))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .monospacedDigit()
            }

            Spacer()

            // Counted
            VStack(alignment: .trailing, spacing: 4) {
                Text("COUNTED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .tracking(1)
                Text(CartMath.formatCents(vm.totalCountedCents))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .spring(duration: DesignTokens.Motion.smooth),
                               value: vm.totalCountedCents)
            }
        }
        .padding(BrandSpacing.lg)
        .overlay(alignment: .bottom) {
            varianceBadge
                .padding(.bottom, -16)
        }
        .padding(.bottom, BrandSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.bizarreSurface1)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(vm.varianceBand.color.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Expected \(CartMath.formatCents(vm.expectedCents)), counted \(CartMath.formatCents(vm.totalCountedCents)), variance \(CartMath.formatCents(vm.varianceCents))"
        )
    }

    private var varianceBadge: some View {
        let v = vm.varianceCents
        let label = v == 0 ? "Balanced" : (v > 0 ? "Over \(CartMath.formatCents(v))" : "Short \(CartMath.formatCents(-v))")
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(vm.varianceBand.color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 3)
            .background(vm.varianceBand.color.opacity(0.15), in: Capsule())
            .animation(reduceMotion ? nil : .spring(duration: DesignTokens.Motion.snappy),
                       value: vm.varianceCents)
    }

    // MARK: - Denomination row

    private func denominationRow(_ binding: Binding<Denomination>) -> some View {
        let denom = binding.wrappedValue
        return HStack(spacing: BrandSpacing.md) {
            Image(systemName: denom.symbol)
                .frame(width: 24)
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)

            Text(denom.label)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .frame(width: 48, alignment: .leading)

            Spacer()

            // Stepper
            HStack(spacing: BrandSpacing.sm) {
                Button {
                    vm.decrement(denom)
                    BrandHaptics.lightImpact()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(denom.count > 0 ? Color.bizarreOnSurface : Color.bizarreOutline)
                }
                .buttonStyle(.plain)
                .disabled(denom.count == 0)
                .accessibilityLabel("Decrease \(denom.label) count")

                Text("\(denom.count)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .frame(minWidth: 32)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .spring(duration: DesignTokens.Motion.snappy),
                               value: denom.count)
                    .accessibilityLabel("\(denom.count) \(denom.label) bills")

                Button {
                    vm.increment(denom)
                    BrandHaptics.lightImpact()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(denom.label) count")
            }

            // Subtotal
            Text(denom.count > 0 ? CartMath.formatCents(denom.subtotalCents) : "—")
                .font(.brandBodyMedium())
                .foregroundStyle(denom.count > 0 ? Color.bizarreOnSurface : Color.bizarreOutline)
                .frame(width: 60, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
    }

    // MARK: - Over-short reason field

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("Over/short reason (required)", systemImage: "exclamationmark.triangle.fill")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreError)

            TextEditor(text: $vm.overShortReason)
                .frame(minHeight: 72)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.bizarreError.opacity(0.5), lineWidth: 1)
                )
                .accessibilityLabel("Over or short reason — required for variance above threshold")
                .accessibilityIdentifier("denomCount.reason")
        }
    }

    // MARK: - Manager PIN banner

    private var managerPinBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: vm.managerPinApproved ? "checkmark.shield.fill" : "lock.shield.fill")
                .foregroundStyle(vm.managerPinApproved ? Color.bizarreSuccess : Color.bizarreWarning)
            Text(vm.managerPinApproved
                 ? "Manager sign-off approved"
                 : "Manager PIN required for this variance")
                .font(.brandBodyMedium())
                .foregroundStyle(vm.managerPinApproved ? Color.bizarreSuccess : Color.bizarreWarning)

            Spacer()

            if !vm.managerPinApproved {
                Button("Enter PIN") { showManagerPin = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.bizarreWarning)
                    .accessibilityIdentifier("denomCount.enterPin")
            }
        }
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill((vm.managerPinApproved ? Color.bizarreSuccess : Color.bizarreWarning).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder((vm.managerPinApproved ? Color.bizarreSuccess : Color.bizarreWarning).opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Preview

#Preview("Denomination Count — Balanced") {
    DenominationCountView(vm: DenominationCountViewModel(expectedCents: 24850))
        .preferredColorScheme(.dark)
}

#Preview("Denomination Count — Over-short") {
    let vm = DenominationCountViewModel(expectedCents: 24850)
    vm.setCount(2, for: Denomination.all[0])  // 2×$100 = $200
    return DenominationCountView(vm: vm)
        .preferredColorScheme(.dark)
}
#endif
