#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairDepositView (Frame 1e)
//
// Step 4: Collect deposit before work begins.
//
// Visual spec: numpad UI matching the full tender screen:
//   - Method strip: "Deposit · $50 of $327" header card
//   - Cash received / Change due display
//   - Quick-amount chips ($50, $60, $75, $100, Exact)
//   - 3×4 numeric keypad
//   - "Confirm deposit" full-width CTA
//
// Server wiring: after deposit confirmed, coordinator calls
// POST /api/v1/tickets/:id/convert-to-invoice.

public struct PosRepairDepositView: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    @State private var depositCoordinator: RepairDepositCoordinator

    // Numpad state — string representation to show trailing zeros correctly
    @State private var inputString: String = ""
    // Quick amount selection for highlight state
    @State private var selectedQuickAmount: Int? = nil

    public init(coordinator: PosRepairFlowCoordinator) {
        self.coordinator = coordinator
        let total = coordinator.draft.estimateCents
        let deposit = coordinator.draft.depositCents > 0
            ? coordinator.draft.depositCents
            : coordinator.draft.suggestedDepositCents
        self._depositCoordinator = State(
            wrappedValue: RepairDepositCoordinator(totalCents: total, defaultDepositCents: deposit)
        )
    }

    // MARK: - Computed

    private var receivedCents: Int {
        Int((Double(inputString) ?? 0) * 100)
    }

    private var changeCents: Int {
        max(0, receivedCents - depositCoordinator.depositCents)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step 4/4 progress bar — full width (100%)
            // Matches the 3pt custom strip used by steps 2 and 3 per mockup 1e.
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(white: 1, opacity: 0.06))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.bizarreOrange, Color.bizarreOrangeBright],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                // Full width (100%) — no geometry reader needed
            }
            .frame(height: 3)
            .accessibilityLabel("Step 4 of 4, 100% complete")

            ScrollView {
                VStack(spacing: 0) {
                    // Method strip card
                    methodStripCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // "Cash received" section label
                    sectionLabel("Cash received")
                        .padding(.horizontal, 16)

                    // Received / Change display
                    cashDisplayPanel

                    // Quick amounts
                    sectionLabel("Quick amount")
                        .padding(.horizontal, 16)

                    quickAmountsRow
                        .padding(.horizontal, 16)

                    // Numpad
                    numpadGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(.bottom, 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Total estimate chip in nav bar (matches mockup chip primary style)
                Text(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.totalCents))
                    .font(.system(size: 14, design: .default).weight(.bold))
                    .foregroundStyle(Color.bizarreOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel("Total estimate: \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.totalCents))")
            }
        }
        .onAppear {
            // Pre-fill input with suggested deposit
            let cents = depositCoordinator.depositCents
            inputString = String(format: "%.2f", Double(cents) / 100.0)
            selectedQuickAmount = cents
        }
        .onChange(of: depositCoordinator.depositCents) { _, newValue in
            coordinator.setDepositCents(newValue)
        }
    }

    // MARK: - Method strip card

    private var methodStripCard: some View {
        HStack(spacing: 10) {
            // Cash icon tile — gradient top:primary-bright → bottom:primary,
            // inner top-edge highlight matches mockup "inset 0 1px 0 rgba(255,255,255,0.6)".
            ZStack {
                LinearGradient(
                    colors: [Color.bizarreOrangeBright, Color.bizarreOrange],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.6), Color.clear],
                                startPoint: .top, endPoint: .center
                            ),
                            lineWidth: 1
                        )
                )
                Text("💵")
                    .font(.system(size: 17))
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Deposit · \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.depositCents)) of \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.totalCents))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.bizarreOrange)
                Text("Balance due at pickup · enter cash received below")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // "Active" chip
            Text("Active")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.bizarreSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreSuccess.opacity(0.35), lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bizarreOrange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bizarreOrange.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cash payment selected. Deposit \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.depositCents)) of \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.totalCents))")
    }

    // MARK: - Cash display panel

    private var cashDisplayPanel: some View {
        HStack {
            // Received column
            VStack(alignment: .leading, spacing: 2) {
                Text("Received")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                cashAmount(inputString)
            }
            Spacer()
            Divider()
                .frame(height: 40)
                .overlay(Color.bizarreOutline.opacity(0.3))
            Spacer()
            // Change column
            VStack(alignment: .trailing, spacing: 2) {
                Text("Change")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                cashAmount(String(format: "$%.2f", Double(changeCents) / 100.0), muted: changeCents == 0)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Received: $\(inputString). Change: \(String(format: "$%.2f", Double(changeCents) / 100.0))")
    }

    private func cashAmount(_ text: String, muted: Bool = false) -> some View {
        // Split main digits from cents (last 3 chars ".00")
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.first.map(String.init) ?? text)
                .font(.system(size: 32, weight: .bold).monospacedDigit())
                .foregroundStyle(muted ? Color.bizarreOnSurfaceMuted : Color.bizarreOnSurface)
            if parts.count > 1 {
                Text("." + String(parts[1]))
                    .font(.system(size: 20, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: - Quick amounts

    private var quickAmountsRow: some View {
        let depositCents = depositCoordinator.depositCents
        let quickAmounts: [(label: String, cents: Int?)] = [
            ("Exact", nil),
            ("$50", 5000),
            ("$60", 6000),
            ("$75", 7500),
            ("$100", 10000),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickAmounts, id: \.label) { item in
                    let isSelected: Bool = {
                        if let itemCents = item.cents {
                            return selectedQuickAmount == itemCents && receivedCents == itemCents
                        } else {
                            return receivedCents == depositCents && selectedQuickAmount == nil
                        }
                    }()
                    Button {
                        if let cents = item.cents {
                            inputString = String(format: "%.2f", Double(cents) / 100.0)
                            selectedQuickAmount = cents
                        } else {
                            // "Exact" — set received to deposit amount
                            inputString = String(format: "%.2f", Double(depositCents) / 100.0)
                            selectedQuickAmount = nil
                        }
                        BrandHaptics.tap()
                    } label: {
                        Text(item.label)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                isSelected ? Color.bizarreOrange : Color.bizarreSurface1,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .foregroundStyle(isSelected ? Color.bizarreOnPrimary : Color.bizarreOnSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        isSelected ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.3),
                                        lineWidth: isSelected ? 0 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label == "Exact" ? "Exact deposit amount" : item.label)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Numpad

    private var numpadGrid: some View {
        let keys: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "⌫"],
        ]
        return VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        numpadKey(key)
                    }
                }
            }
        }
    }

    private func numpadKey(_ key: String) -> some View {
        Button {
            handleNumpadKey(key)
            BrandHaptics.tap()
        } label: {
            Text(key)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    key == "⌫"
                        ? Color.bizarreOnSurfaceMuted
                        : Color.bizarreOnSurface
                )
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == "⌫" ? "Delete" : key == "." ? "Decimal point" : key)
    }

    private func handleNumpadKey(_ key: String) {
        selectedQuickAmount = nil
        switch key {
        case "⌫":
            if !inputString.isEmpty {
                inputString.removeLast()
                if inputString.isEmpty { inputString = "0" }
            }
        case ".":
            if !inputString.contains(".") {
                if inputString.isEmpty { inputString = "0" }
                inputString += "."
            }
        default:
            if inputString == "0" {
                inputString = key
            } else {
                // Cap decimal places at 2
                if let dotIdx = inputString.firstIndex(of: ".") {
                    let decimals = inputString.distance(from: dotIdx, to: inputString.endIndex) - 1
                    if decimals < 2 { inputString += key }
                } else {
                    inputString += key
                }
            }
        }
    }

    // MARK: - CTA bar

    private var ctaBar: some View {
        VStack(spacing: 8) {
            if let error = coordinator.errorMessage ?? depositCoordinator.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                // Record the received amount, then confirm deposit
                depositCoordinator.onTendered = { tendered in
                    coordinator.setDepositCents(tendered)
                    coordinator.advance()
                }
                depositCoordinator.confirmDeposit()
                BrandHaptics.tapMedium()
            } label: {
                HStack(spacing: 6) {
                    if coordinator.isLoading || depositCoordinator.isProcessing {
                        ProgressView().tint(Color.bizarreOnPrimary)
                    } else {
                        Text("Confirm deposit")
                            .font(.subheadline.weight(.bold))
                        // Amount badge per mockup "tb-amount" class
                        Text(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.depositCents))
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .opacity(0.85)
                        Text("›")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (coordinator.isLoading || depositCoordinator.isProcessing || depositCoordinator.depositCents <= 0)
                        ? Color.bizarreOrange.opacity(0.4)
                        : Color.bizarreOrange,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(Color.bizarreOnPrimary)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isLoading || depositCoordinator.isProcessing || depositCoordinator.depositCents <= 0)
            .sensoryFeedback(.success, trigger: coordinator.isComplete)
            .accessibilityLabel("Confirm deposit of \(RepairDepositCoordinator.formatCurrency(cents: depositCoordinator.depositCents))")
            .accessibilityIdentifier("repairFlow.deposit.collect")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(Color.bizarreOnSurfaceMuted)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
#endif
