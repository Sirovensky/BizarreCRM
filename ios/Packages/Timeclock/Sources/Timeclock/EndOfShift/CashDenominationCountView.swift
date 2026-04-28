import SwiftUI
import DesignSystem
import Core

// MARK: - CashDenominationCountView

/// §14.10 — Cash-count step of the end-of-shift flow.
///
/// Cashier enters how many of each US denomination they have.
/// Over/short is computed live against the expected amount from the server.
///
/// Layout: iPhone full-screen scroll; iPad 2-column split (denominations | summary).
public struct CashDenominationCountView: View {

    @Bindable var vm: EndShiftSummaryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: EndShiftSummaryViewModel) { self.vm = vm }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Count Cash")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                overShortBanner
                denominationList
                handoffSection
                continueButton
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.md) {
                    denominationList
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: 380)
            Divider()
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    overShortBanner
                    handoffSection
                    continueButton
                }
                .padding(BrandSpacing.base)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var overShortBanner: some View {
        let overShort = vm.liveOverShortCents
        let isOver    = overShort >= 0
        let absVal    = abs(overShort)
        let color: Color = overShort == 0 ? .bizarreSuccess
                         : absVal > 200    ? .bizarreError
                                           : .bizarreWarning
        let label = overShort == 0 ? "Balanced ✓"
                  : "\(isOver ? "Over" : "Short"): \(String(format: "$%.2f", Double(absVal) / 100))"

        return HStack {
            Image(systemName: overShort == 0 ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandBodyLarge().weight(.semibold))
                    .foregroundStyle(color)
                if absVal > 200 {
                    Text("Manager sign-off required")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            if let expected = vm.summary?.cashExpectedCents {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Expected")
                        .font(.brandCaption1())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(String(format: "$%.2f", Double(expected) / 100))
                        .font(.brandBodyLarge().monospacedDigit())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Over/short: \(label)")
    }

    private var denominationList: some View {
        VStack(spacing: BrandSpacing.xs) {
            ForEach($vm.denominations) { $denom in
                DenominationRow(denomination: $denom)
            }
        }
    }

    @ViewBuilder
    private var handoffSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Opening cash for next cashier (optional)")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack {
                Text("$")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("0.00", value: Binding(
                    get: { Double(vm.handoffCashCents) / 100 },
                    set: { vm.handoffCashCents = Int($0 * 100) }
                ), format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .font(.brandBodyLarge().monospacedDigit())
                .accessibilityLabel("Opening cash for next cashier")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var continueButton: some View {
        Button {
            vm.finishCashCount()
        } label: {
            Text(vm.requiresManagerSignOff ? "Continue to Manager Sign-off" : "Close Shift")
                .font(.brandBodyLarge().weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.brandGlass)
        .accessibilityLabel(vm.requiresManagerSignOff ? "Continue to manager sign-off" : "Close shift")
    }
}

// MARK: - DenominationRow

private struct DenominationRow: View {
    @Binding var denomination: CashDenomination

    var body: some View {
        HStack {
            Text(denomination.label)
                .font(.brandBodyLarge().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
                .frame(width: 52, alignment: .leading)

            Spacer()

            // Stepper with explicit value display
            HStack(spacing: BrandSpacing.sm) {
                Button {
                    if denomination.count > 0 { denomination.count -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(denomination.count > 0 ? Color.bizarreOrange : .bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Decrease \(denomination.label) count")

                Text("\(denomination.count)")
                    .font(.brandBodyLarge().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(width: 36, alignment: .center)
                    .accessibilityLabel("\(denomination.count) \(denomination.label) bills")

                Button {
                    denomination.count += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Increase \(denomination.label) count")
            }

            Spacer()

            Text(String(format: "$%.2f", Double(denomination.totalCents) / 100))
                .font(.brandBodyLarge().monospacedDigit())
                .foregroundStyle(denomination.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                .frame(width: 64, alignment: .trailing)
                .accessibilityLabel("\(denomination.label) total: \(String(format: "$%.2f", Double(denomination.totalCents) / 100))")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
    }
}
