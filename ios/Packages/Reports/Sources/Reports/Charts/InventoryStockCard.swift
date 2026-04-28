import SwiftUI
import Charts
import DesignSystem

// MARK: - InventoryStockCard
//
// §15.5 — Low stock / out-of-stock counts + Inventory value (cost + retail).
// Uses InventoryReport already fetched by ReportsViewModel.

public struct InventoryStockCard: View {
    public let report: InventoryReport
    public let isLoading: Bool

    public init(report: InventoryReport, isLoading: Bool = false) {
        self.report = report
        self.isLoading = isLoading
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if isLoading {
                skeletonState
            } else if sizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Inventory Stock Health")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            stockCountRow
            if !report.valueSummary.isEmpty {
                Divider().overlay(Color.bizarreOutline.opacity(0.4))
                inventoryValueSection
            }
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                stockCountRow
            }
            .frame(maxWidth: .infinity)

            if !report.valueSummary.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    inventoryValueSection
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Stock count KPI row

    private var stockCountRow: some View {
        HStack(spacing: BrandSpacing.md) {
            stockKPI(
                label: "Out of Stock",
                value: "\(report.outOfStockCount)",
                icon: "exclamationmark.circle.fill",
                color: report.outOfStockCount > 0 ? Color.bizarreError : Color.bizarreSuccess
            )
            stockKPI(
                label: "Low Stock",
                value: "\(report.lowStockCount)",
                icon: "exclamationmark.triangle.fill",
                color: report.lowStockCount > 0 ? Color.bizarreWarning : Color.bizarreSuccess
            )
        }
    }

    private func stockKPI(label: String, value: String,
                          icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(value)
                .font(.brandHeadlineMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.sm)
        .background(color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Inventory value section

    private var inventoryValueSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Inventory Value")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            let totalCost = report.valueSummary.reduce(0) { $0 + $1.totalCostValue }
            let totalRetail = report.valueSummary.reduce(0) { $0 + $1.totalRetailValue }
            let margin = totalCost > 0 ? (totalRetail - totalCost) / totalCost * 100.0 : 0

            HStack(spacing: BrandSpacing.md) {
                valueKPI(label: "Cost Value", value: formatCurrency(totalCost), color: .bizarreTeal)
                valueKPI(label: "Retail Value", value: formatCurrency(totalRetail), color: .bizarreOrange)
                valueKPI(label: "Markup", value: String(format: "%.0f%%", margin), color: .bizarreSuccess)
            }

            // Per-category chart if available
            if !report.valueSummary.isEmpty {
                valueChart
            }
        }
    }

    private func valueKPI(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Value breakdown bar chart

    private var valueChart: some View {
        Chart(report.valueSummary) { entry in
            BarMark(
                x: .value("Retail Value", entry.totalRetailValue / 1_000.0),
                y: .value("Category", entry.itemType)
            )
            .foregroundStyle(Color.bizarreOrange.opacity(0.75))
            .cornerRadius(DesignTokens.Radius.xs)
            .annotation(position: .trailing) {
                Text(formatCurrencyCompact(entry.totalRetailValue))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .chartXAxisLabel("Retail Value ($K)", alignment: .center)
        .frame(height: max(CGFloat(report.valueSummary.count) * 32, 80))
        .accessibilityLabel("Inventory value breakdown by category")
    }

    // MARK: - Skeleton

    private var skeletonState: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2)
                    .frame(height: 20)
                    .opacity(0.6)
            }
        }
        .accessibilityLabel("Loading inventory stock data")
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        if v >= 1_000_000 {
            return String(format: "$%.1fM", v / 1_000_000)
        }
        if v >= 1_000 {
            return String(format: "$%.1fK", v / 1_000)
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func formatCurrencyCompact(_ v: Double) -> String {
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }
}
