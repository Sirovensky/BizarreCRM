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
            emptySparklineSilhouette
        } else {
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
            .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                       value: topItems.count)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurface)
                }
            }
        }
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

    // MARK: - Empty state

    /// Dashed bar silhouette when zero data points (§91.13 item 5).
    private var emptySparklineSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barWidths: [CGFloat] = [0.7, 0.55, 0.45, 0.38, 0.28]
            let step = h / CGFloat(barWidths.count + 1)
            Path { path in
                for (i, frac) in barWidths.enumerated() {
                    let y = step * CGFloat(i + 1)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w * frac, y: y))
                }
            }
            .stroke(
                Color.bizarreOnSurface.opacity(0.18),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [10, 5])
            )
        }
        .overlay(alignment: .center) {
            Text("No data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("No inventory movement data for this period")
    }

    private var emptyState: some View {
        ContentUnavailableView("No Movement Data",
                               systemImage: "shippingbox",
                               description: Text("No inventory movement data for this period."))
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
