import SwiftUI
import Charts
import DesignSystem

// MARK: - RevenueByMethodCard
//
// §91.2-6: Surface a clear explanation when `byMethod` is empty but overall
// revenue is non-zero — data comes from a separate aggregation path on the
// server (report.byMethod vs report.totals.totalRevenue). The card shows a
// tooltip-style notice so the user understands this is a data-source lag,
// not a UI bug.
//
// When `byMethod` contains rows the card renders a donut + legend list.
// Wired to SalesReportResponse.byMethod from GET /api/v1/reports/sales.

public struct RevenueByMethodCard: View {
    public let methods: [PaymentMethodPoint]
    /// Overall revenue total (from SalesTotals) — used to detect mismatch.
    public let totalRevenueDollars: Double

    public init(methods: [PaymentMethodPoint], totalRevenueDollars: Double) {
        self.methods = methods
        self.totalRevenueDollars = totalRevenueDollars
    }

    // Pie-slice colors cycling through brand palette.
    private let sliceColors: [Color] = [
        .bizarreOrange, .bizarreTeal, .bizarreSuccess, .bizarreError,
        .bizarreOrange.opacity(0.6), .bizarreTeal.opacity(0.6)
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack {
                Image(systemName: "creditcard")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Revenue by Method")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }

            Divider()

            if methods.isEmpty {
                emptyState
            } else {
                dataView
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        // §91.2-6: When revenue is nonzero but no method breakdown is available,
        // explain the data-source mismatch instead of showing bare "No payment data".
        if totalRevenueDollars > 0 {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Breakdown pending")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Revenue of \(compactCurrency(totalRevenueDollars)) is recorded but the payment-method breakdown hasn't been aggregated yet for this period. Pull to refresh or check back shortly.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Revenue breakdown pending. Revenue recorded: \(compactCurrency(totalRevenueDollars)). Payment method data not yet available.")
        } else {
            ContentUnavailableView(
                "No Payment Data",
                systemImage: "creditcard.slash",
                description: Text("No payment transactions in the selected period.")
            )
        }
    }

    // MARK: - Data view (donut + list)

    private var dataView: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Donut chart
            Chart(methods) { point in
                SectorMark(
                    angle: .value("Revenue", point.revenue),
                    innerRadius: .ratio(0.55),
                    outerRadius: .ratio(1.0)
                )
                .foregroundStyle(sliceColor(for: point))
                .accessibilityLabel("\(point.method): \(compactCurrency(point.revenue))")
            }
            .frame(width: 110, height: 110)
            .accessibilityChartDescriptor(MethodChartDescriptor(methods: methods))

            // Legend list
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(methods) { point in
                    HStack(spacing: BrandSpacing.xs) {
                        Circle()
                            .fill(sliceColor(for: point))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(point.method)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer(minLength: 0)
                        Text(compactCurrency(point.revenue))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(point.method): \(compactCurrency(point.revenue))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func sliceColor(for point: PaymentMethodPoint) -> Color {
        let idx = methods.firstIndex(where: { $0.id == point.id }) ?? 0
        return sliceColors[idx % sliceColors.count]
    }

    private func compactCurrency(_ dollars: Double) -> String {
        if dollars >= 1_000 {
            let k = dollars / 1_000.0
            return k < 10
                ? String(format: "$%.1fK", k)
                : String(format: "$%.0fK", k)
        }
        return String(format: "$%.0f", dollars)
    }
}

// MARK: - AXChartDescriptor

private struct MethodChartDescriptor: AXChartDescriptorRepresentable {
    let methods: [PaymentMethodPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Payment Method",
            categoryOrder: methods.map(\.method)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Revenue (USD)",
            range: 0...(methods.map(\.revenue).max() ?? 0),
            gridlinePositions: []
        ) { val in String(format: "$%.2f", val) }
        let series = AXDataSeriesDescriptor(
            name: "Revenue by Method",
            isContinuous: false,
            dataPoints: methods.map { pt in
                AXDataPoint(x: pt.method, y: pt.revenue)
            }
        )
        return AXChartDescriptor(
            title: "Revenue by Payment Method",
            summary: "Donut chart of revenue split by payment method",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
