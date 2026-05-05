#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - WeeklyCashFlow model

/// §39.5 — Seven-day cash-flow summary used by the weekly tile.
///
/// Contains aggregated cash-in / cash-out / net figures for the trailing
/// 7 calendar days, plus a day-by-day breakdown for a small bar sparkline.
public struct WeeklyCashFlow: Sendable, Equatable {

    /// One calendar day's figures.
    public struct DayEntry: Sendable, Equatable, Identifiable {
        public let id: String          // "YYYY-MM-DD"
        public let date: Date
        public let cashInCents: Int
        public let cashOutCents: Int
        public var netCents: Int { cashInCents - cashOutCents }

        public init(id: String, date: Date, cashInCents: Int, cashOutCents: Int) {
            self.id = id
            self.date = date
            self.cashInCents = cashInCents
            self.cashOutCents = cashOutCents
        }
    }

    public let days: [DayEntry]        // 7 entries, oldest → newest
    public var totalCashInCents: Int   { days.reduce(0) { $0 + $1.cashInCents } }
    public var totalCashOutCents: Int  { days.reduce(0) { $0 + $1.cashOutCents } }
    public var netCents: Int           { totalCashInCents - totalCashOutCents }
    public var isPositive: Bool        { netCents >= 0 }

    public init(days: [DayEntry]) {
        self.days = days
    }

    // MARK: - Sample data

    public static func sample() -> WeeklyCashFlow {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries: [DayEntry] = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            return DayEntry(
                id: df.string(from: date),
                date: date,
                cashInCents: Int.random(in: 30_000...120_000),
                cashOutCents: Int.random(in: 5_000...40_000)
            )
        }
        return WeeklyCashFlow(days: entries)
    }
}

// MARK: - WeeklyCashFlowTile

/// §39.5 — Dashboard tile showing 7-day cash-flow summary.
///
/// Renders:
///  - Total cash-in / cash-out / net for the trailing week
///  - Colour-coded net (green positive, red negative)
///  - Compact day-bar sparkline (cash-in green bars + cash-out red bars)
///
/// Intended for embedding in the reconciliation dashboard or POS home metrics
/// row. Tapping the tile navigates to `ReconciliationDashboardView`.
public struct WeeklyCashFlowTile: View {

    public let flow: WeeklyCashFlow
    public var onTap: (() -> Void)?

    public init(flow: WeeklyCashFlow, onTap: (() -> Void)? = nil) {
        self.flow = flow
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        Button {
            onTap?()
            BrandHaptics.lightImpact()
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("weeklyCashFlow.tile")
        .accessibilityAddTraits(.isButton)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Title row
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Weekly cash flow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.5)
                    .textCase(.uppercase)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }

            // Net headline
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                Text(CartMath.formatCents(abs(flow.netCents)))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(flow.isPositive ? .bizarreSuccess : .bizarreError)
                    .monospacedDigit()
                Text(flow.isPositive ? "net in" : "net out")
                    .font(.brandLabelSmall())
                    .foregroundStyle(flow.isPositive ? .bizarreSuccess : .bizarreError)
            }

            // In / out sub-row
            HStack(spacing: BrandSpacing.lg) {
                labelledAmount(
                    label: "In",
                    cents: flow.totalCashInCents,
                    color: .bizarreSuccess,
                    icon: "arrow.down.circle.fill"
                )
                labelledAmount(
                    label: "Out",
                    cents: flow.totalCashOutCents,
                    color: .bizarreError,
                    icon: "arrow.up.circle.fill"
                )
                Spacer()
            }

            // Sparkline
            sparkline
                .frame(height: 32)
        }
        .padding(BrandSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.bizarreSurface1)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(
                            flow.isPositive
                                ? Color.bizarreSuccess.opacity(0.2)
                                : Color.bizarreError.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        GeometryReader { geo in
            let barWidth = max(1, (geo.size.width / CGFloat(max(flow.days.count, 1))) - 2)
            let maxCents = flow.days.map { max($0.cashInCents, $0.cashOutCents) }.max() ?? 1
            let scale = geo.size.height / CGFloat(max(maxCents, 1))

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(flow.days) { day in
                    VStack(alignment: .center, spacing: 1) {
                        // Cash-in bar (green, bottom-up)
                        Capsule()
                            .fill(Color.bizarreSuccess.opacity(0.7))
                            .frame(
                                width: barWidth * 0.45,
                                height: max(2, CGFloat(day.cashInCents) * scale)
                            )
                            .accessibilityHidden(true)
                        // Cash-out bar (red, overlapping bottom half)
                        Capsule()
                            .fill(Color.bizarreError.opacity(0.6))
                            .frame(
                                width: barWidth * 0.45,
                                height: max(2, CGFloat(day.cashOutCents) * scale)
                            )
                            .accessibilityHidden(true)
                    }
                    .frame(width: barWidth)
                }
            }
        }
    }

    // MARK: - Helpers

    private func labelledAmount(label: String, cents: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.3)
                Text(CartMath.formatCents(cents))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
    }

    private var accessibilityDescription: String {
        let net = CartMath.formatCents(abs(flow.netCents))
        let direction = flow.isPositive ? "net in" : "net out"
        let inAmt = CartMath.formatCents(flow.totalCashInCents)
        let outAmt = CartMath.formatCents(flow.totalCashOutCents)
        return "Weekly cash flow: \(net) \(direction). Cash in \(inAmt), cash out \(outAmt). Tap for full report."
    }
}

// MARK: - Preview

#Preview("Weekly cash flow tile") {
    VStack {
        WeeklyCashFlowTile(flow: .sample()) {
            print("Tapped weekly tile")
        }
        .padding()
    }
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
