import SwiftUI
import Core
import Charts
import DesignSystem

// MARK: - RevenueByMethodPieCard
//
// §15.2 — Revenue by payment method pie chart.
// Wired to byMethod[] from GET /api/v1/reports/sales.

public struct RevenueByMethodPieCard: View {
    public let points: [PaymentMethodPoint]

    public init(points: [PaymentMethodPoint]) {
        self.points = points
    }

    @State private var selectedMethod: String?

    private let palette: [Color] = [
        .bizarreOrange, .bizarrePrimary, .bizarreSuccess,
        .bizarreInfo, .bizarreWarning, .bizarreError
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Revenue by Method")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if points.isEmpty {
                emptyState
            } else {
                if Platform.isCompact {
                    phoneLayout
                } else {
                    ipadLayout
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - iPhone: pie above legend

    private var phoneLayout: some View {
        VStack(spacing: BrandSpacing.md) {
            pieChart
                .frame(height: 180)
            legend
        }
    }

    // MARK: - iPad: pie left, legend right

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.xl) {
            pieChart
                .frame(width: 180, height: 180)
            legend
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pie chart

    private var pieChart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { idx, point in
                SectorMark(
                    angle: .value("Revenue", point.revenue),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(color(for: idx))
                .opacity(selectedMethod == nil || selectedMethod == point.method ? 1 : 0.35)
            }
        }
        .chartAngleSelection(value: $selectedMethod)
        .chartBackground { proxy in
            // Centre label: selected method name or total
            if let method = selectedMethod,
               let point = points.first(where: { $0.method == method }) {
                VStack(spacing: 2) {
                    Text(friendlyName(for: point.method))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                    Text(formatCurrency(point.revenue))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .frame(maxWidth: 80)
            } else {
                let total = points.reduce(0) { $0 + $1.revenue }
                VStack(spacing: 2) {
                    Text("Total")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(formatCurrency(total))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityChartDescriptor(PaymentMethodPieDescriptor(points: points))
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(Array(points.enumerated()), id: \.element.id) { idx, point in
                let total = points.reduce(0) { $0 + $1.revenue }
                let pct = total > 0 ? (point.revenue / total * 100) : 0
                Button {
                    withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                        selectedMethod = selectedMethod == point.method ? nil : point.method
                    }
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: idx))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(friendlyName(for: point.method))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatCurrency(point.revenue))
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .monospacedDigit()
                            Text(String(format: "%.1f%%", pct))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .monospacedDigit()
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(friendlyName(for: point.method)): \(formatCurrency(point.revenue)), \(String(format: "%.1f", pct)) percent"
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No payment data for this period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(.vertical, BrandSpacing.xl)
        .accessibilityLabel("No payment method data available for this period")
    }

    // MARK: - Helpers

    private func color(for idx: Int) -> Color {
        palette[idx % palette.count]
    }

    private func friendlyName(for method: String) -> String {
        switch method.lowercased() {
        case "cash":         return "Cash"
        case "card":         return "Card"
        case "gift_card":    return "Gift Card"
        case "store_credit": return "Store Credit"
        case "check":        return "Check"
        case "ach":          return "ACH"
        default:             return method.capitalized
        }
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v >= 10_000 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - AXChartDescriptorRepresentable

private struct PaymentMethodPieDescriptor: AXChartDescriptorRepresentable {
    let points: [PaymentMethodPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let total = points.reduce(0) { $0 + $1.revenue }
        let series = AXDataSeriesDescriptor(
            name: "Revenue by payment method",
            isContinuous: false,
            dataPoints: points.map { pt in
                AXDataPoint(
                    x: pt.method,
                    y: pt.revenue,
                    label: String(format: "%.1f%%", total > 0 ? pt.revenue / total * 100 : 0)
                )
            }
        )
        return AXChartDescriptor(
            title: "Revenue by Payment Method",
            summary: "Pie chart of revenue split across \(points.count) payment methods",
            xAxis: AXCategoricalDataAxisDescriptor(
                title: "Payment method",
                categoryOrder: points.map { $0.method }
            ),
            yAxis: AXNumericDataAxisDescriptor(
                title: "Revenue (USD)",
                range: 0...max(1, total),
                gridlinePositions: []
            ) { "$\(String(format: "%.2f", $0))" },
            series: [series]
        )
    }
}
