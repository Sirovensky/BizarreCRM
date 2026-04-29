import SwiftUI
import Charts
import DesignSystem

// MARK: - InventoryMovementCard
//
// Wired to GET /api/v1/reports/inventory (via ReportsRepository.getInventoryReport).
// Shows a horizontal BarMark of top-10 moving items by units used.
// Also surfaces out-of-stock and low-stock alert counts.
//
// iPhone: single column, chart below KPI row.
// iPad: chart (left) + value summary table (right) 2-up.

public struct InventoryMovementCard: View {
    public let report: InventoryReport?

    public init(report: InventoryReport?) {
        self.report = report
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topItems: [InventoryMovementItem] {
        guard let r = report else { return [] }
        return Array(r.topMoving.sorted { $0.usedQty > $1.usedQty }.prefix(10))
    }

    /// §91.12 (5): total retail value across all value-summary entries.
    private func totalInventoryValue(_ r: InventoryReport) -> Double {
        r.valueSummary.reduce(0) { $0 + $1.totalRetailValue }
    }

    /// §91.12 (5): true when OOS count > 0 but aggregate inventory value is $0.
    /// This is contradictory — items can't be "out of stock" if inventory is unvalued.
    private func isStockHealthContradiction(_ r: InventoryReport) -> Bool {
        r.outOfStockCount > 0 && totalInventoryValue(r) == 0
    }

    public var body: some View {
        if sizeClass == .regular {
            ipadBody
        } else {
            phoneBody
        }
    }

    // MARK: - iPhone layout

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            alertRow
            stockHealthWarning
            movementChart
                .frame(height: max(160, Double(topItems.count) * 28))
                .chartXAxisLabel("Units Used (30d)", alignment: .center)
                .accessibilityLabel(axLabel)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad 2-up layout

    private var ipadBody: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Left: movement bar chart
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                cardHeader
                stockHealthWarning
                movementChart
                    .frame(height: max(200, Double(topItems.count) * 28))
                    .chartXAxisLabel("Units Used (30d)", alignment: .center)
                    .accessibilityLabel(axLabel)
            }
            .frame(maxWidth: .infinity)

            // Right: value summary table
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Stock Value")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
                alertRow
                if let r = report {
                    valueSummaryTable(r.valueSummary)
                }
            }
            .frame(maxWidth: 200)
            .padding(.top, BrandSpacing.xxs)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Card header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Inventory Movement")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("Top 10 · 30d")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Stock health contradiction warning (§91.12 item 5)

    @ViewBuilder
    private var stockHealthWarning: some View {
        if let r = report, isStockHealthContradiction(r) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text("Stock health contradiction: \(r.outOfStockCount) out-of-stock items reported but inventory value is $0. Check data sync.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Stock health contradiction: \(r.outOfStockCount) out-of-stock items but inventory value is zero. Check data sync."
            )
        }
    }

    // MARK: - Alert row (out of stock / low stock)

    @ViewBuilder
    private var alertRow: some View {
        if let r = report, (r.outOfStockCount > 0 || r.lowStockCount > 0) {
            HStack(spacing: BrandSpacing.sm) {
                if r.outOfStockCount > 0 {
                    alertChip(
                        count: r.outOfStockCount,
                        label: "Out of stock",
                        icon: "exclamationmark.circle.fill",
                        color: .bizarreError
                    )
                }
                if r.lowStockCount > 0 {
                    alertChip(
                        count: r.lowStockCount,
                        label: "Low stock",
                        icon: "arrow.down.circle.fill",
                        color: .bizarreWarning
                    )
                }
            }
        }
    }

    private func alertChip(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("\(count) \(label)")
                .font(.brandLabelSmall())
        }
        .foregroundStyle(color)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(count) items \(label)")
    }

    // MARK: - Movement bar chart (horizontal)

    @ViewBuilder
    private var movementChart: some View {
        if topItems.isEmpty {
            ChartDashedSilhouette(systemImage: "shippingbox", label: "No inventory movement data for this period.")
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Chart(topItems) { item in
                    BarMark(
                        x: .value("Units Used", item.usedQty),
                        y: .value("Item", item.name)
                    )
                    .foregroundStyle(Color.bizarreTeal.opacity(0.75))
                    .cornerRadius(DesignTokens.Radius.xs)
                    .annotation(position: .trailing) {
                        Text("\(item.usedQty)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.bizarreOnSurface.opacity(0.85))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                           value: topItems.count)

                inventoryLegendRow
            }
        }
    }

    private var inventoryLegendRow: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(Color.bizarreTeal.opacity(0.75)).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("Units used (30d)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: units used in last 30 days")
    }

    // MARK: - Value summary table (iPad sidebar)

    @ViewBuilder
    private func valueSummaryTable(_ entries: [InventoryValueEntry]) -> some View {
        if entries.isEmpty {
            Text("No value data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.itemType.capitalized)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                            Text(entry.totalRetailValue, format: .currency(code: "USD"))
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("retail")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .frame(minHeight: DesignTokens.Touch.minTargetSide)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(entry.itemType.capitalized): \(entry.itemCount) items, retail value \(String(format: "$%.2f", entry.totalRetailValue))"
                    )
                    Divider()
                }
            }
        }
    }


    // MARK: - Helpers

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }

    private var axLabel: String {
        guard let r = report else { return "Inventory movement chart — no data." }
        return "Top \(topItems.count) most-used inventory items in last 30 days. Out of stock: \(r.outOfStockCount). Low stock: \(r.lowStockCount)."
    }
}
