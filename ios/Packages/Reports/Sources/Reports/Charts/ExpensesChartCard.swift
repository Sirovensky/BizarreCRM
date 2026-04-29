import SwiftUI
import Charts
import DesignSystem

// MARK: - ExpensesChartCard
//
// Wired to GET /api/v1/reports/dashboard-kpis (via ReportsRepository.getExpensesReport).
// Shows a stacked BarMark of revenue vs COGS per day, plus headline expense total
// and gross margin badge.
//
// iPhone: single column card.
// iPad: two-column, chart left / KPI summary right.

public struct ExpensesChartCard: View {
    public let report: ExpensesReport?

    public init(report: ExpensesReport?) {
        self.report = report
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        if sizeClass == .regular {
            ipadBody
        } else {
            phoneBody
        }
    }

    // MARK: - Phone layout

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            kpiRow
            chartContent
                .frame(height: 160)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Amount ($)", position: .leading)
                .accessibilityLabel(axLabel)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad 2-up layout

    private var ipadBody: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                cardHeader
                chartContent
                    .frame(height: 200)
                    .chartXAxisLabel("Date", alignment: .center)
                    .chartYAxisLabel("Amount ($)", position: .leading)
                    .accessibilityLabel(axLabel)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Summary")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
                kpiStack
                    .frame(maxWidth: 180)
            }
            .padding(.top, BrandSpacing.xxs)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Expenses & Margin")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if let m = report?.marginPct {
                marginBadge(m)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func marginBadge(_ pct: Double) -> some View {
        let isGood = pct > 30
        Text(String(format: "%.1f%% margin", pct))
            .font(.brandLabelLarge())
            .foregroundStyle(isGood ? Color.bizarreSuccess : Color.bizarreWarning)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                (isGood ? Color.bizarreSuccess : Color.bizarreWarning).opacity(0.12),
                in: Capsule()
            )
            .accessibilityLabel("Gross margin \(String(format: "%.1f", pct)) percent")
    }

    // MARK: - KPI row (iPhone)

    @ViewBuilder
    private var kpiRow: some View {
        if let r = report {
            HStack(spacing: BrandSpacing.md) {
                kpiCell(label: "Revenue", value: r.revenueDollars, color: .bizarreTeal)
                kpiCell(label: "Expenses", value: r.totalDollars, color: .bizarreWarning)
                kpiCell(label: "Profit", value: r.grossProfitDollars,
                        color: r.grossProfitDollars >= 0 ? .bizarreSuccess : .bizarreError)
            }
        }
    }

    // MARK: - KPI stack (iPad sidebar)

    @ViewBuilder
    private var kpiStack: some View {
        if let r = report {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                kpiCell(label: "Revenue", value: r.revenueDollars, color: .bizarreTeal)
                Divider()
                kpiCell(label: "Expenses", value: r.totalDollars, color: .bizarreWarning)
                Divider()
                kpiCell(label: "Gross Profit", value: r.grossProfitDollars,
                        color: r.grossProfitDollars >= 0 ? .bizarreSuccess : .bizarreError)
            }
        }
    }

    private func kpiCell(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value, format: .currency(code: "USD"))
                .font(.brandTitleSmall())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(String(format: "$%.2f", value))")
    }

    // MARK: - Chart content

    @ViewBuilder
    private var chartContent: some View {
        if let r = report, !r.dailyBreakdown.isEmpty {
            chartBody(r)
        } else {
            emptySparklineSilhouette
        }
    }

    @ViewBuilder
    private func chartBody(_ r: ExpensesReport) -> some View {
        Chart(r.dailyBreakdown) { day in
            // Revenue bar (teal)
            BarMark(
                x: .value("Date", day.date),
                y: .value("Revenue", day.revenue),
                stacking: .standard
            )
            .foregroundStyle(Color.bizarreTeal.opacity(0.75))
            .cornerRadius(DesignTokens.Radius.xs)

            // COGS bar (warning, stacked below revenue to show cost component)
            BarMark(
                x: .value("Date", day.date),
                y: .value("COGS", day.cogs),
                stacking: .standard
            )
            .foregroundStyle(Color.bizarreWarning.opacity(0.55))
            .cornerRadius(DesignTokens.Radius.xs)
        }
        .chartForegroundStyleScale([
            "Revenue": Color.bizarreTeal.opacity(0.75),
            "COGS": Color.bizarreWarning.opacity(0.55)
        ])
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bizarreOnSurface)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                   value: r.dailyBreakdown.count)
        // Legend — explicit color-name + value a11y (§91.13 item 4)
        legendRow(r)
    }

    private func legendRow(_ r: ExpensesReport) -> some View {
        HStack(spacing: BrandSpacing.md) {
            legendChip(label: "Revenue", color: .bizarreTeal, value: r.revenueDollars)
            legendChip(label: "COGS", color: .bizarreWarning, value: r.totalDollars)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Chart legend: Revenue (teal) \(String(format: "$%.2f", r.revenueDollars)), COGS (amber) \(String(format: "$%.2f", r.totalDollars))"
        )
    }

    private func legendChip(label: String, color: Color, value: Double) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(label) \(value, format: .currency(code: "USD"))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Empty state

    /// Dashed sparkline silhouette shown when there are zero data points (§91.13 item 5).
    private var emptySparklineSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Two gentle humps representing the stacked bar silhouette
            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.7))
                path.addCurve(
                    to: CGPoint(x: w * 0.4, y: h * 0.4),
                    control1: CGPoint(x: w * 0.15, y: h * 0.6),
                    control2: CGPoint(x: w * 0.25, y: h * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.55),
                    control1: CGPoint(x: w * 0.6, y: h * 0.45),
                    control2: CGPoint(x: w * 0.8, y: h * 0.6)
                )
            }
            .stroke(
                Color.bizarreOnSurface.opacity(0.18),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: 0)
            )
        }
        .overlay(alignment: .center) {
            Text("No data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("No expense data for this period")
    }

    private var emptyState: some View {
        // ContentUnavailableView wrapped per-character in narrow columns on
        // landscape iPad (Bebas display font + tight container). Roll a small
        // VStack with `lineLimit` + `minimumScaleFactor` so the labels stay
        // legible at any width.
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No expense data")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("No data for this period.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No expense data for this period")
    }

    // MARK: - Helpers

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }

    private var axLabel: String {
        guard let r = report else { return "Expenses chart — no data." }
        return String(format: "Expenses and revenue chart. Total expenses $%.2f, revenue $%.2f.",
                      r.totalDollars, r.revenueDollars)
    }
}
