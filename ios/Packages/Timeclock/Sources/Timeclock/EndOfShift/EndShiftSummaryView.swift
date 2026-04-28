import SwiftUI
import DesignSystem
import Core

// MARK: - EndShiftSummaryView

/// §14.10 — Multi-step end-of-shift flow entry point.
///
/// Shows the cashier:
///   1. Summary of sales, gross, tips, items sold, voids for the shift.
///   2. Cash denomination count with live over/short.
///   3. Manager PIN sign-off if |over/short| > $2.00.
///   4. Confirmation + optional Z-report link.
///
/// Sovereignty: all data from tenant server only.
///
/// Layout:
/// - iPhone: NavigationStack full-screen.
/// - iPad: NavigationStack as panel in split or sheet.
public struct EndShiftSummaryView: View {

    @Bindable var vm: EndShiftSummaryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(vm: EndShiftSummaryViewModel) { self.vm = vm }

    public var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .loadingStats:
                    loadingView

                case .summaryReview:
                    summaryReviewView

                case .cashCount:
                    CashDenominationCountView(vm: vm)

                case .managerSignOff:
                    managerSignOffView

                case .confirming:
                    confirmingView

                case .done(let shiftId):
                    doneView(shiftId: shiftId)

                case .failed(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("End Shift")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step != .done(0) && vm.step != .confirming {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .task { await vm.loadStats() }
    }

    // MARK: - Steps

    private var loadingView: some View {
        ProgressView("Loading shift summary…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var summaryReviewView: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                if let s = vm.summary {
                    shiftKPIGrid(summary: s)
                }
                Text("Tap \"Count Cash\" to proceed to the cash close-out.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)

                Button {
                    vm.proceedToCashCount()
                } label: {
                    Text("Count Cash")
                        .font(.brandBodyLarge().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                }
                .buttonStyle(.brandGlass)
                .padding(.horizontal, BrandSpacing.base)
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var managerSignOffView: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Over/short warning
                overShortWarning

                // Reason field
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Reason (required)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    TextField("Explain the over/short…", text: $vm.overShortReason, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.brandBodyMedium())
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Over/short reason")
                }

                // Manager PIN
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Manager PIN")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    SecureField("Enter manager PIN", text: $vm.managerPin)
                        .keyboardType(.numberPad)
                        .font(.brandBodyLarge().monospacedDigit())
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Manager PIN field")

                    if let err = vm.managerPinError {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }

                Button {
                    Task { await vm.verifyManagerPin() }
                } label: {
                    Text("Confirm & Close Shift")
                        .font(.brandBodyLarge().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                }
                .buttonStyle(.brandGlass)
                .disabled(vm.overShortReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || vm.managerPin.isEmpty)
                .accessibilityLabel("Confirm and close shift")
            }
            .padding(BrandSpacing.base)
        }
        .navigationTitle("Manager Sign-off")
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var confirmingView: some View {
        ProgressView("Closing shift…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func doneView(shiftId: Int64) -> some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)

            Text("Shift closed")
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOnSurface)

            if let s = vm.summary {
                shiftKPIGrid(summary: s)
            }

            if vm.handoffCashCents > 0 {
                Text("Opening cash of \(String(format: "$%.2f", Double(vm.handoffCashCents) / 100)) handed off.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            // §14.10 — Z-report PDF link: shown when the server archived a Z-report
            // for this shift close (§39 Cash register feature).  Opens the PDF in the
            // default browser / PDF viewer via the tenant's authenticated API URL.
            if let zURL = vm.zReportURL() {
                Button {
                    openURL(zURL)
                } label: {
                    Label("View Z-Report", systemImage: "doc.text.fill")
                        .font(.brandBodyLarge().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                }
                .buttonStyle(.brandGlass)
                .padding(.horizontal, BrandSpacing.xl)
                .accessibilityLabel("View Z-Report PDF for this shift")
            }

            Button("Done") { dismiss() }
                .font(.brandBodyLarge().weight(.semibold))
                .buttonStyle(.brandGlass)
                .padding(.horizontal, BrandSpacing.xl)
                .accessibilityLabel("Done — dismiss end of shift screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Could not load shift summary")
                .font(.brandBodyLarge().weight(.semibold))
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Retry") { Task { await vm.loadStats() } }
                .font(.brandBodyLarge())
                .buttonStyle(.brandGlass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Reusable components

    @ViewBuilder
    private func shiftKPIGrid(summary: EndShiftSummary) -> some View {
        LazyVGrid(columns: Platform.isCompact
                      ? [GridItem(.flexible()), GridItem(.flexible())]
                      : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  spacing: BrandSpacing.md) {
            KPITile(icon: "cart.fill",
                    label: "Sales",
                    value: "\(summary.salesCount)",
                    a11y: "\(summary.salesCount) sales")
            KPITile(icon: "dollarsign.circle.fill",
                    label: "Gross",
                    value: summary.formatted(cents: summary.grossCents),
                    a11y: "Gross \(summary.formatted(cents: summary.grossCents))")
            KPITile(icon: "hand.thumbsup.fill",
                    label: "Tips",
                    value: summary.formatted(cents: summary.tipsCents),
                    a11y: "Tips \(summary.formatted(cents: summary.tipsCents))")
            KPITile(icon: "shippingbox.fill",
                    label: "Items sold",
                    value: "\(summary.itemsSold)",
                    a11y: "\(summary.itemsSold) items sold")
            KPITile(icon: "xmark.circle.fill",
                    label: "Voids",
                    value: "\(summary.voidCount)",
                    a11y: "\(summary.voidCount) voids",
                    valueColor: summary.voidCount > 0 ? .bizarreWarning : .bizarreOnSurface)
            if summary.cashCountedCents > 0 || vm.step == .done(0) {
                KPITile(icon: summary.overShortCents >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                        label: "Over/Short",
                        value: summary.overShortLabel,
                        a11y: "Over short \(summary.overShortLabel)",
                        valueColor: abs(summary.overShortCents) > 200 ? .bizarreError : .bizarreSuccess)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    private var overShortWarning: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Over/short exceeds $2.00")
                    .font(.brandBodyLarge().weight(.semibold))
                    .foregroundStyle(.bizarreError)
                let abs = abs(vm.liveOverShortCents)
                Text("\(String(format: "$%.2f", Double(abs) / 100)) — manager approval required")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - KPITile

private struct KPITile: View {
    let icon: String
    let label: String
    let value: String
    let a11y: String
    var valueColor: Color = .bizarreOnSurface

    var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(value)
                .font(.brandBodyLarge().weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.brandCaption())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}
