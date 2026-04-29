#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - End-of-shift summary card model

/// §39 (Discovered §14 lines 1777-1782) — Shift summary shown when cashier
/// taps "End shift". Aggregates key metrics and compares with prior shifts.
///
/// Sovereignty: all shift data stays on the tenant server only (`APIClient.baseURL`).
/// No third-party analytics or remote telemetry endpoints touched.
public struct EndOfShiftCard: Sendable, Equatable {
    /// Current shift figures
    public let saleCount: Int
    public let grossCents: Int       // revenue before discounts
    public let tipsCents: Int
    public let cashExpectedCents: Int
    public let voidsCents: Int
    public let itemsSoldCount: Int

    /// Prior-shift comparison (nil when no prior shift on record)
    public let priorGrossCents: Int?
    public let priorSaleCount: Int?

    public init(
        saleCount: Int,
        grossCents: Int,
        tipsCents: Int,
        cashExpectedCents: Int,
        voidsCents: Int,
        itemsSoldCount: Int,
        priorGrossCents: Int? = nil,
        priorSaleCount: Int? = nil
    ) {
        self.saleCount = saleCount
        self.grossCents = grossCents
        self.tipsCents = tipsCents
        self.cashExpectedCents = cashExpectedCents
        self.voidsCents = voidsCents
        self.itemsSoldCount = itemsSoldCount
        self.priorGrossCents = priorGrossCents
        self.priorSaleCount = priorSaleCount
    }

    // MARK: - Trend helpers

    /// Percentage change in gross vs prior shift. Nil when no prior data.
    public var grossTrendPercent: Double? {
        guard let prior = priorGrossCents, prior > 0 else { return nil }
        return Double(grossCents - prior) / Double(prior) * 100
    }

    public var saleCountTrendPercent: Double? {
        guard let prior = priorSaleCount, prior > 0 else { return nil }
        return Double(saleCount - prior) / Double(prior) * 100
    }
}

// MARK: - EndOfShiftSummaryView

/// §39 (Discovered §14 lines 1777-1782) — Cashier-facing "End shift" summary card.
///
/// Shown when cashier taps "End shift" from the POS home screen.  Includes:
/// - Sales count / gross / tips / cash expected / cash counted (entered by cashier) / over-short / items sold / voids
/// - Trend arrows vs prior shift for gross + sale count
/// - CTA: "Count drawer" → DenominationCountView
/// - CTA: "View Z-report" → ZReportView / ShiftSummaryView
/// - CTA: "Start handoff" → ShiftHandoffView
///
/// Over-short threshold (>$2) requires reason + manager PIN (gate in DenominationCountView).
///
/// iPhone: modal sheet.
/// iPad: `.medium` detent sheet, 540pt ideal width.
@MainActor
public struct EndOfShiftSummaryView: View {

    public let card: EndOfShiftCard
    public let shiftSummary: ShiftSummary?   // nil while server response pending
    public var onCountDrawer: (() -> Void)?
    public var onViewZReport: (() -> Void)?
    public var onStartHandoff: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    // §14 — shift-summary copy button state
    @State private var didCopySummary: Bool = false

    public init(
        card: EndOfShiftCard,
        shiftSummary: ShiftSummary? = nil,
        onCountDrawer: (() -> Void)? = nil,
        onViewZReport: (() -> Void)? = nil,
        onStartHandoff: (() -> Void)? = nil
    ) {
        self.card = card
        self.shiftSummary = shiftSummary
        self.onCountDrawer = onCountDrawer
        self.onViewZReport = onViewZReport
        self.onStartHandoff = onStartHandoff
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    headerSection
                    metricsGrid
                    trendSection
                    ctaSection
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("End Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityIdentifier("endShift.cancel")
                }
                // §14 — shift-summary copy button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = shiftSummaryText
                        BrandHaptics.success()
                        didCopySummary = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            didCopySummary = false
                        }
                    } label: {
                        Label(
                            didCopySummary ? "Copied" : "Copy",
                            systemImage: didCopySummary ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .accessibilityLabel(didCopySummary ? "Summary copied to clipboard" : "Copy shift summary to clipboard")
                    .accessibilityIdentifier("endShift.copy")
                }
            }
        }
        .frame(idealWidth: Platform.isCompact ? nil : 540)
    }

    // MARK: - §14 Copy helper

    /// Plain-text representation of shift metrics for clipboard copy.
    private var shiftSummaryText: String {
        var lines: [String] = [
            "Shift Summary",
            "─────────────────",
            "Gross sales:   \(CartMath.formatCents(card.grossCents))",
            "Sale count:    \(card.saleCount)",
            "Tips:          \(CartMath.formatCents(card.tipsCents))",
            "Cash expected: \(CartMath.formatCents(card.cashExpectedCents))",
            "Items sold:    \(card.itemsSoldCount)",
            "Voids:         \(CartMath.formatCents(card.voidsCents))",
        ]
        if let gross = card.grossTrendPercent {
            let sign = gross >= 0 ? "+" : ""
            lines.append("Gross vs prior: \(sign)\(String(format: "%.1f", gross))%")
        }
        if let count = card.saleCountTrendPercent {
            let sign = count >= 0 ? "+" : ""
            lines.append("Sales vs prior: \(sign)\(String(format: "%.1f", count))%")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "moon.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOrange)
                .padding(.top, BrandSpacing.lg)
                .accessibilityHidden(true)

            Text("Shift Complete")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)

            Text("Review your numbers before closing the register.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.md),
                       GridItem(.flexible(), spacing: BrandSpacing.md)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            metricTile(label: "Gross sales",
                       value: CartMath.formatCents(card.grossCents),
                       icon: "dollarsign.circle.fill",
                       color: .bizarreSuccess,
                       id: "endShift.gross")

            metricTile(label: "Sale count",
                       value: "\(card.saleCount)",
                       icon: "cart.fill",
                       color: .bizarreOrange,
                       id: "endShift.saleCount")

            metricTile(label: "Tips",
                       value: CartMath.formatCents(card.tipsCents),
                       icon: "heart.fill",
                       color: .bizarreTeal,
                       id: "endShift.tips")

            metricTile(label: "Cash expected",
                       value: CartMath.formatCents(card.cashExpectedCents),
                       icon: "banknote.fill",
                       color: .bizarreOnSurface,
                       id: "endShift.cashExpected")

            metricTile(label: "Items sold",
                       value: "\(card.itemsSoldCount)",
                       icon: "shippingbox.fill",
                       color: .bizarreOnSurface,
                       id: "endShift.itemsSold")

            metricTile(label: "Voids",
                       value: CartMath.formatCents(card.voidsCents),
                       icon: "xmark.circle.fill",
                       color: card.voidsCents > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted,
                       id: "endShift.voids")
        }
    }

    private func metricTile(
        label: String,
        value: String,
        icon: String,
        color: Color,
        id: String
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(id)
    }

    // MARK: - Trend section

    @ViewBuilder
    private var trendSection: some View {
        if card.grossTrendPercent != nil || card.saleCountTrendPercent != nil {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("VS. PRIOR SHIFT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(1)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: BrandSpacing.md) {
                    if let grossTrend = card.grossTrendPercent {
                        trendChip(label: "Gross", percent: grossTrend)
                    }
                    if let countTrend = card.saleCountTrendPercent {
                        trendChip(label: "Sales", percent: countTrend)
                    }
                    Spacer()
                }
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private func trendChip(label: String, percent: Double) -> some View {
        let positive = percent >= 0
        let color: Color = positive ? .bizarreSuccess : .bizarreError
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let formatted = String(format: "%.1f%%", abs(percent))
        return HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.system(size: 11, weight: .bold))
            Text("\(label) \(formatted)")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(label) \(positive ? "up" : "down") \(formatted) vs prior shift")
    }

    // MARK: - CTA section

    private var ctaSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            // Primary: count drawer
            Button {
                onCountDrawer?()
            } label: {
                Label("Count drawer", systemImage: "dollarsign.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("endShift.countDrawer")

            HStack(spacing: BrandSpacing.sm) {
                // View Z-report
                Button {
                    onViewZReport?()
                } label: {
                    Label("Z-Report", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreTeal)
                .accessibilityIdentifier("endShift.zReport")

                // Handoff
                Button {
                    onStartHandoff?()
                } label: {
                    Label("Hand off", systemImage: "arrow.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("endShift.handoff")
            }

            // Sovereignty note — reassures staff data stays on their server
            Label(
                "Shift data stored on your server only",
                systemImage: "lock.shield"
            )
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.top, BrandSpacing.xs)
            .accessibilityIdentifier("endShift.sovereigntyNote")
        }
    }
}

// MARK: - Preview

#Preview("End of Shift — with trends") {
    EndOfShiftSummaryView(
        card: EndOfShiftCard(
            saleCount: 47,
            grossCents: 312_49,
            tipsCents: 18_50,
            cashExpectedCents: 84_00,
            voidsCents: 12_99,
            itemsSoldCount: 63,
            priorGrossCents: 280_00,
            priorSaleCount: 42
        ),
        shiftSummary: nil
    )
    .preferredColorScheme(.dark)
}

#Preview("End of Shift — first shift") {
    EndOfShiftSummaryView(
        card: EndOfShiftCard(
            saleCount: 12,
            grossCents: 89_99,
            tipsCents: 0,
            cashExpectedCents: 45_00,
            voidsCents: 0,
            itemsSoldCount: 15
        )
    )
    .preferredColorScheme(.dark)
}
#endif
