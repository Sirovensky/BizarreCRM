import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - ExpenseSummaryHeaderView

/// Polished summary header shown at the top of the expense list.
///
/// Renders differently on iPhone vs iPad:
/// - **iPhone (compact)**: vertical stack — hero amount, count, horizontal category chips row.
/// - **iPad (regular)**: single `Grid` row — hero amount | count | category chips side-by-side.
///
/// Uses `CategoryBreakdown` from `ExpensesListResponse` when available.
/// If the server returns no category breakdown the category row is hidden.
public struct ExpenseSummaryHeaderView: View {

    // MARK: - Input

    public let summary: ExpensesListResponse.Summary
    /// Optional per-category totals. Currently sourced from a local tally of
    /// `items` in the list because the existing API response already decodes
    /// `expenses` — we compute the breakdown client-side from that array.
    public let categoryTotals: [CategoryTotal]

    public struct CategoryTotal: Identifiable {
        public let id: String  // category string
        public let total: Double
        public let count: Int

        public init(category: String, total: Double, count: Int) {
            self.id = category
            self.total = total
            self.count = count
        }
    }

    // MARK: - Init

    public init(summary: ExpensesListResponse.Summary, categoryTotals: [CategoryTotal]) {
        self.summary = summary
        self.categoryTotals = categoryTotals
    }

    // MARK: - Body

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - Compact layout (iPhone)

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            heroAmountRow
            if !categoryTotals.isEmpty {
                categoryScrollRow
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Regular layout (iPad)

    private var regularLayout: some View {
        Grid(alignment: .topLeading, horizontalSpacing: BrandSpacing.xl, verticalSpacing: 0) {
            GridRow {
                // Column 1: hero amount + count
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    heroAmountRow
                }
                .gridColumnAlignment(.leading)

                // Column 2: category breakdown (scrollable)
                if !categoryTotals.isEmpty {
                    categoryBreakdownColumn
                        .gridColumnAlignment(.leading)
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Shared sub-views

    private var heroAmountRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Total Spend")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Text(formatMoney(summary.totalAmount))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel("Total spend \(formatMoney(summary.totalAmount))")
            }
            Spacer(minLength: BrandSpacing.sm)
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("Expenses")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text("\(summary.totalCount)")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .accessibilityLabel("\(summary.totalCount) expenses")
            }
        }
    }

    private var categoryScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(categoryTotals.prefix(6)) { cat in
                    CategoryChip(category: cat)
                }
            }
            .padding(.vertical, BrandSpacing.xxs)
        }
    }

    private var categoryBreakdownColumn: some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            // §11.1 Category breakdown pie (iPad/Mac)
            if categoryTotals.count >= 2 {
                CategoryPieChart(categoryTotals: Array(categoryTotals.prefix(6)))
                    .frame(width: 120, height: 120)
                    .accessibilityLabel("Category breakdown pie chart")
            }
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("By Category")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    ForEach(categoryTotals.prefix(6)) { cat in
                        CategoryChip(category: cat)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - CategoryChip

// MARK: - §11.1 Category Pie Chart (iPad/Mac)

/// `Chart.SectorMark` pie showing spend share by category.
/// `AXChartDescriptorRepresentable` provides a11y description.
private struct CategoryPieChart: View {
    let categoryTotals: [ExpenseSummaryHeaderView.CategoryTotal]

    private static let palette: [Color] = [
        .bizarreOrange,
        .bizarreSuccess,
        .bizarreWarning,
        .bizarreError,
        Color(red: 0.4, green: 0.6, blue: 0.9),
        Color(red: 0.7, green: 0.4, blue: 0.9)
    ]

    var body: some View {
        Chart(Array(categoryTotals.enumerated()), id: \.element.id) { idx, cat in
            SectorMark(
                angle: .value("Amount", cat.total),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(Self.palette[idx % Self.palette.count])
            .accessibilityLabel("\(cat.id.capitalized): \(Int(cat.total)) dollars")
        }
        .accessibilityChartDescriptor(PieChartDescriptor(categoryTotals: categoryTotals))
    }
}

private struct PieChartDescriptor: AXChartDescriptorRepresentable {
    let categoryTotals: [ExpenseSummaryHeaderView.CategoryTotal]

    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(
            name: "Expenses by category",
            isContinuous: false,
            dataPoints: categoryTotals.map { cat in
                AXDataPoint(
                    x: cat.id.capitalized,
                    y: cat.total,
                    additionalValues: [],
                    label: "\(cat.id.capitalized): \(Int(cat.total)) dollars"
                )
            }
        )
        return AXChartDescriptor(
            title: "Expenses by category",
            summary: "Pie chart of spending by category",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Category", categoryOrder: categoryTotals.map { $0.id.capitalized }),
            yAxis: AXNumericDataAxisDescriptor(title: "Amount", range: 0...((categoryTotals.max(by: { $0.total < $1.total })?.total ?? 1) * 1.1), gridlinePositions: []) { v in "$\(Int(v))" },
            series: [series]
        )
    }
}

private struct CategoryChip: View {
    let category: ExpenseSummaryHeaderView.CategoryTotal

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(category.id.capitalized)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnOrange)
                .lineLimit(1)
            Text(Self.moneyFormatter.string(from: NSNumber(value: category.total)) ?? "$\(Int(category.total))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnOrange.opacity(0.85))
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.id.capitalized): \(Self.moneyFormatter.string(from: NSNumber(value: category.total)) ?? "")")
    }
}

// MARK: - Static factory

public extension ExpenseSummaryHeaderView {
    /// Derives `categoryTotals` from an array of loaded expenses.
    static func categoryTotals(from expenses: [Expense]) -> [CategoryTotal] {
        var totals: [String: (Double, Int)] = [:]
        for exp in expenses {
            let key = exp.category ?? "Other"
            let prev = totals[key] ?? (0, 0)
            totals[key] = (prev.0 + (exp.amount ?? 0), prev.1 + 1)
        }
        return totals
            .map { CategoryTotal(category: $0.key, total: $0.value.0, count: $0.value.1) }
            .sorted { $0.total > $1.total }
    }
}
