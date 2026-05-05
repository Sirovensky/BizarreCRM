import SwiftUI
import DesignSystem

// MARK: - AvgTicketValueCard

public struct AvgTicketValueCard: View {
    public let value: AvgTicketValue?
    /// Total revenue for the period in dollars (§91.12 item 2 inconsistency check).
    public let periodRevenueDollars: Double
    /// Number of closed tickets used to derive the average (§91.12 item 2).
    public let ticketCount: Int

    public init(value: AvgTicketValue?,
                periodRevenueDollars: Double = 0,
                ticketCount: Int = 0) {
        self.value = value
        self.periodRevenueDollars = periodRevenueDollars
        self.ticketCount = ticketCount
    }

    /// §91.12 (2): revenue > 0 but ticketCount == 0 means the avgTicket math is wrong.
    private var isDataInconsistent: Bool {
        periodRevenueDollars > 0 && ticketCount == 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            // §91.12 (2): warn before showing the (misleading) $0.00 value
            if isDataInconsistent {
                dataInconsistencyWarning
            } else if let v = value {
                metricRow(v)
            } else {
                ChartDashedSilhouette(systemImage: "dollarsign.circle.fill", label: "No ticket value data for this period.")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Data inconsistency warning (§91.12 item 2)

    private var dataInconsistencyWarning: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Data inconsistent — revenue recorded but ticket count is zero.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data inconsistent: revenue is recorded but ticket count is zero. Average ticket value cannot be calculated.")
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("Avg Ticket Value")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func metricRow(_ v: AvgTicketValue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.md) {
            // §91.10: unified KPI value token; monospacedDigit prevents jitter
            Text(v.currentDollars, format: .currency(code: "USD"))
                .font(.brandKpiValue())
                .monospacedDigit()
                .foregroundStyle(.bizarreOnSurface)

            trendBadge(pct: v.trendPct)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Average ticket value: \(String(format: "$%.2f", v.currentDollars)), trend \(trendDescription(v.trendPct))"
        )

        Text("vs \(v.previousDollars, format: .currency(code: "USD")) prior period")
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }

    @ViewBuilder
    private func trendBadge(pct: Double) -> some View {
        // §91.3 fix 4: show "–" (em-dash) when delta is zero — avoids misleading "↗ 0.0%".
        if pct == 0 {
            Text("–")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreOnSurfaceMuted.opacity(0.10), in: Capsule())
        } else {
            let isUp = pct > 0
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(String(format: "%.1f%%", abs(pct)))
                    .font(.brandLabelLarge())
            }
            .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background((isUp ? Color.bizarreSuccess : Color.bizarreError).opacity(0.12), in: Capsule())
        }
    }

    private func trendDescription(_ pct: Double) -> String {
        guard pct != 0 else { return "no change" }
        let dir = pct > 0 ? "up" : "down"
        return "\(dir) \(String(format: "%.1f", abs(pct))) percent"
    }
}
