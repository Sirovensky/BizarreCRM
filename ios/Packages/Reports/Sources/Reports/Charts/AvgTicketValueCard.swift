import SwiftUI
import DesignSystem

// MARK: - AvgTicketValueCard

public struct AvgTicketValueCard: View {
    public let value: AvgTicketValue?

    public init(value: AvgTicketValue?) {
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if let v = value {
                metricRow(v)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Loading average ticket value")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
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
            Text(v.currentDollars, format: .currency(code: "USD"))
                .font(.brandHeadlineMedium())
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
        let isUp = pct >= 0
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

    private func trendDescription(_ pct: Double) -> String {
        let dir = pct >= 0 ? "up" : "down"
        return "\(dir) \(String(format: "%.1f", abs(pct))) percent"
    }
}
