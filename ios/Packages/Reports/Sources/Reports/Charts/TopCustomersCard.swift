import SwiftUI
import Charts
import DesignSystem

// MARK: - TopCustomerRow
//
// §15.2 — Top 10 customers by spend.
// Mapped from GET /api/v1/reports/top-customers (or derived from GET /api/v1/reports/customers).

public struct TopCustomerRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let revenueDollars: Double
    public let invoiceCount: Int
    public let lastPurchaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case revenueDollars  = "revenue"
        case invoiceCount    = "invoice_count"
        case lastPurchaseDate = "last_purchase_date"
    }

    public init(id: Int64, name: String, revenueDollars: Double,
                invoiceCount: Int, lastPurchaseDate: String? = nil) {
        self.id = id
        self.name = name
        self.revenueDollars = revenueDollars
        self.invoiceCount = invoiceCount
        self.lastPurchaseDate = lastPurchaseDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.revenueDollars = (try? c.decode(Double.self, forKey: .revenueDollars)) ?? 0
        self.invoiceCount = (try? c.decode(Int.self, forKey: .invoiceCount)) ?? 0
        self.lastPurchaseDate = try? c.decode(String.self, forKey: .lastPurchaseDate)
    }
}

// MARK: - TopCustomersCard

public struct TopCustomersCard: View {
    public let rows: [TopCustomerRow]
    public let onTapCustomer: (Int64) -> Void

    public init(rows: [TopCustomerRow], onTapCustomer: @escaping (Int64) -> Void = { _ in }) {
        self.rows = rows
        self.onTapCustomer = onTapCustomer
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if rows.isEmpty {
                emptyState
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
            Image(systemName: "person.3.sequence.fill")
                .foregroundStyle(.bizarreMagenta)
                .accessibilityHidden(true)
            Text("Top 10 Customers by Spend")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - iPhone: ranked list + bar mini-chart

    private var phoneLayout: some View {
        VStack(spacing: BrandSpacing.xs) {
            let top = Array(rows.prefix(10))
            let maxRev = top.first?.revenueDollars ?? 1.0
            ForEach(Array(top.enumerated()), id: \.element.id) { idx, row in
                Button {
                    onTapCustomer(row.id)
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        rankBadge(rank: idx + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.bizarreMagenta.opacity(0.3))
                                    .frame(
                                        width: geo.size.width * CGFloat(row.revenueDollars / maxRev),
                                        height: 4
                                    )
                            }
                            .frame(height: 4)
                        }
                        Spacer()
                        Text(formatCurrency(row.revenueDollars))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Rank \(idx + 1): \(row.name), \(formatCurrency(row.revenueDollars)), \(row.invoiceCount) invoices"
                )
            }
        }
    }

    // MARK: - iPad: bar chart + rank list side-by-side

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Bar chart column
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Revenue")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                barChart
                    .frame(height: min(CGFloat(rows.prefix(10).count) * 28, 280))
                    .accessibilityChartDescriptor(TopCustomersChartDescriptor(rows: Array(rows.prefix(10))))
            }
            .frame(maxWidth: .infinity)

            // Rank list column
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Rank")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { idx, row in
                    HStack {
                        rankBadge(rank: idx + 1)
                        Text(row.name)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)
                        Spacer()
                        Text("\(row.invoiceCount) inv.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCustomer(row.id) }
                    .hoverEffect(.highlight)
                }
            }
            .frame(maxWidth: 180)
        }
    }

    // MARK: - Horizontal bar chart (shared for iPad column 1)

    private var barChart: some View {
        Chart(Array(rows.prefix(10))) { row in
            BarMark(
                x: .value("Revenue", row.revenueDollars / 1_000.0),
                y: .value("Customer", row.name)
            )
            .foregroundStyle(Color.bizarreMagenta.opacity(0.8))
            .cornerRadius(DesignTokens.Radius.xxs)
        }
        .chartXAxisLabel("Revenue ($K)", alignment: .center)
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                   value: rows.count)
    }

    // MARK: - Rank badge

    private func rankBadge(rank: Int) -> some View {
        Text("#\(rank)")
            .font(.brandMono(size: 11))
            .foregroundStyle(rank <= 3 ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
            .frame(width: 28, alignment: .leading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Customer Data",
            systemImage: "person.3.sequence.fill",
            description: Text("No customer spend data for this period.")
        )
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - AXChartDescriptor

private struct TopCustomersChartDescriptor: AXChartDescriptorRepresentable {
    let rows: [TopCustomerRow]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Revenue (USD)",
            range: 0...(rows.map(\.revenueDollars).max() ?? 1),
            gridlinePositions: []
        ) { String(format: "$%.0f", $0) }
        let yAxis = AXCategoricalDataAxisDescriptor(
            title: "Customer",
            categoryOrder: rows.map(\.name)
        )
        let series = AXDataSeriesDescriptor(
            name: "Top Customers", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.revenueDollars, y: 0, label: $0.name) }
        )
        return AXChartDescriptor(
            title: "Top 10 Customers by Spend",
            summary: "Horizontal bar chart showing top customers ranked by total revenue",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
