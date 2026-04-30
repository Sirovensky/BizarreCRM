import SwiftUI
import Charts
import DesignSystem

// MARK: - CohortRevenueRetentionCard
//
// §91.2-7: Bottom safe-area padding so the card is never cut off by home
// indicator or tab bar chrome.
//
// Shows per-cohort revenue retention as a heat-grid:
//   rows    = cohort month (join date)
//   columns = months since join (M+0 … M+N)
//   cell    = retention % (0–100) colour-coded green→orange→red.
//
// Data source: computed client-side from RevenuePoint series grouped by
// the cohort's first-purchase month. Server does not expose a dedicated
// cohort endpoint yet.

// MARK: - CohortRevenueRow model (public for preview / testing)

public struct CohortRevenueRow: Identifiable, Sendable {
    public let id: String          // cohort label, e.g. "Jan 25"
    public let label: String
    /// Retention percentages indexed by months-since-join (index 0 = M+0).
    public let retention: [Double]

    public init(label: String, retention: [Double]) {
        self.id = label
        self.label = label
        self.retention = retention
    }
}

// MARK: - Card view

public struct CohortRevenueRetentionCard: View {

    public let cohorts: [CohortRevenueRow]
    /// Maximum number of month columns to render (default 6).
    public var maxMonths: Int = 6

    public init(cohorts: [CohortRevenueRow], maxMonths: Int = 6) {
        self.cohorts = cohorts
        self.maxMonths = maxMonths
    }

    // Column header labels: M+0, M+1, …
    private var columnHeaders: [String] {
        (0..<maxMonths).map { "M+\($0)" }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Card header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Cohort Revenue Retention")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }

            Divider()

            if cohorts.isEmpty {
                ContentUnavailableView(
                    "No Cohort Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Not enough history to build a retention grid.")
                )
            } else {
                retentionGrid
            }
        }
        .padding(BrandSpacing.base)
        // §91.2-7: bottom safe-area padding so last row isn't clipped by
        // tab bar / home indicator when the card sits at the bottom of the scroll.
        .padding(.bottom, BrandSpacing.safeAreaBottomPadding)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cohort Revenue Retention grid, \(cohorts.count) cohorts")
    }

    // MARK: - Retention grid

    private var retentionGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                // Column header row
                HStack(spacing: BrandSpacing.xxs) {
                    Text("")
                        .frame(width: 52)
                    ForEach(columnHeaders, id: \.self) { header in
                        Text(header)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                    }
                }

                // Data rows
                ForEach(cohorts) { cohort in
                    HStack(spacing: BrandSpacing.xxs) {
                        Text(cohort.label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .frame(width: 52, alignment: .leading)
                            .lineLimit(1)

                        ForEach(0..<maxMonths, id: \.self) { col in
                            let pct = col < cohort.retention.count ? cohort.retention[col] : nil
                            retentionCell(pct: pct, cohort: cohort.label, month: columnHeaders[col])
                        }
                    }
                }
            }
            .padding(.bottom, BrandSpacing.xs)
        }
    }

    // MARK: - Individual cell

    private func retentionCell(pct: Double?, cohort: String, month: String) -> some View {
        Group {
            if let pct {
                Text(String(format: "%.0f%%", pct))
                    // §91.13: minimum 12 pt for Dynamic Type compliance.
                    // Previously `.system(size: 11)` which failed legibility test.
                    .font(.brandChartAxisLabel().monospacedDigit())
                    .foregroundStyle(cellTextColor(pct: pct))
                    .frame(width: 44, height: 30)
                    .background(cellBackground(pct: pct), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .accessibilityLabel("\(cohort) \(month): \(Int(pct)) percent retention")
            } else {
                Color.bizarreSurface1
                    .frame(width: 44, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .accessibilityLabel("\(cohort) \(month): no data")
            }
        }
    }

    private func cellBackground(pct: Double) -> Color {
        switch pct {
        case 80...: return .bizarreSuccess.opacity(0.75)
        case 50..<80: return .bizarreOrange.opacity(0.55)
        default:    return .bizarreError.opacity(0.45)
        }
    }

    private func cellTextColor(pct: Double) -> Color {
        pct >= 50 ? .bizarreSurfaceBase : .bizarreOnSurface
    }
}

// MARK: - BrandSpacing safe-area helper
// Single-spot constant; replace with actual token if DesignSystem exposes one.

private extension BrandSpacing {
    /// Generous bottom padding so the last card clears tab bar + home indicator.
    static var safeAreaBottomPadding: CGFloat { 32 }
}
