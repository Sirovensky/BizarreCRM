#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - CustomerStatsHeader

/// §5.1 Stats header — total customers / VIPs / at-risk / total LTV / avg LTV.
/// Shown when `showStats` is toggled on in the toolbar.
public struct CustomerStatsHeader: View {
    public let stats: CustomerListStats

    public init(stats: CustomerListStats) {
        self.stats = stats
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                if let total = stats.totalCustomers {
                    statTile(label: "Total", value: "\(total)", icon: "person.2")
                }
                if let vip = stats.vipCount {
                    statTile(label: "VIP", value: "\(vip)", icon: "star.fill", tint: .bizarreOrange)
                }
                if let atRisk = stats.atRiskCount {
                    statTile(label: "At-risk", value: "\(atRisk)", icon: "exclamationmark.triangle.fill", tint: .bizarreError)
                }
                if let totalLtv = stats.totalLtvCents {
                    statTile(label: "Total LTV", value: formatCents(totalLtv), icon: "chart.line.uptrend.xyaxis")
                }
                if let avgLtv = stats.avgLtvCents {
                    statTile(label: "Avg LTV", value: formatCents(avgLtv), icon: "dollarsign.circle")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityElement(children: .contain)
    }

    private func statTile(
        label: String,
        value: String,
        icon: String,
        tint: Color = .bizarreOnSurfaceMuted
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatCents(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$?"
    }
}
#endif
