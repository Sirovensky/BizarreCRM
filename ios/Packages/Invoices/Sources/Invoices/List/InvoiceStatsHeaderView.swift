#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// §7.1 Invoice stats header
// iPhone: horizontal scroll of 4 KPI tiles
// iPad/Mac: same KPI row + two SectorMark pie charts

public struct InvoiceStatsHeaderView: View {
    @State private var vm: InvoiceStatsViewModel
    let onTileTap: ((InvoiceStatsTile) -> Void)?

    public init(api: APIClient, onTileTap: ((InvoiceStatsTile) -> Void)? = nil) {
        _vm = State(wrappedValue: InvoiceStatsViewModel(api: api))
        self.onTileTap = onTileTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                ProgressView()
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
            } else if let stats = vm.stats {
                if Platform.isCompact {
                    iPhoneStatsRow(stats: stats)
                } else {
                    iPadStatsLayout(stats: stats)
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: - iPhone: horizontal scroll of KPI chips

    private func iPhoneStatsRow(stats: InvoiceStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                statTile(.outstanding, value: stats.outstandingDollars, color: .bizarreError)
                statTile(.overdue, value: stats.overdueDollars, color: .bizarreWarning)
                statTile(.paid, value: stats.paidDollars, color: .bizarreSuccess)
                statTile(.avgValue, value: stats.avgValueDollars, color: .bizarreOrange)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .padding(.vertical, BrandSpacing.sm)
    }

    // MARK: - iPad: KPI row + pies

    private func iPadStatsLayout(stats: InvoiceStats) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            // KPI row
            HStack(spacing: BrandSpacing.sm) {
                statTile(.outstanding, value: stats.outstandingDollars, color: .bizarreError)
                statTile(.overdue, value: stats.overdueDollars, color: .bizarreWarning)
                statTile(.paid, value: stats.paidDollars, color: .bizarreSuccess)
                statTile(.avgValue, value: stats.avgValueDollars, color: .bizarreOrange)
            }
            .padding(.horizontal, BrandSpacing.base)

            // Pie charts
            HStack(spacing: BrandSpacing.base) {
                statusPieCard(stats: stats)
                paymentMethodPieCard(stats: stats)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .padding(.vertical, BrandSpacing.sm)
    }

    // MARK: - Individual stat tile

    private func statTile(_ tile: InvoiceStatsTile, value: Double, color: Color) -> some View {
        Button {
            onTileTap?(tile)
        } label: {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tile.label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatMoney(value))
                    .font(.brandTitleMedium())
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .padding(BrandSpacing.sm)
            .frame(minWidth: 100, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tile.label): \(formatMoney(value))")
        .accessibilityHint("Tap to filter by \(tile.label.lowercased())")
    }

    // MARK: - Status pie (iPad/Mac only)

    private func statusPieCard(stats: InvoiceStats) -> some View {
        let data: [(label: String, value: Double, color: Color)] = [
            ("Outstanding", stats.outstandingDollars, .bizarreError),
            ("Paid",        stats.paidDollars,        .bizarreSuccess),
            ("Overdue",     stats.overdueDollars,     .bizarreWarning),
        ].filter { $0.value > 0 }

        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("By status")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Chart(data, id: \.label) { item in
                SectorMark(
                    angle: .value("Amount", item.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                .accessibilityLabel("\(item.label): \(formatMoney(item.value))")
            }
            .chartLegend(.hidden)
            .frame(height: 110)
            .accessibilityChartDescriptor(StatusPieDescriptor(data: data))
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Payment method pie (iPad/Mac only)

    private func paymentMethodPieCard(stats: InvoiceStats) -> some View {
        let data = stats.byPaymentMethod
            .sorted { $0.value > $1.value }
            .map { (label: $0.key.capitalized, value: $0.value) }

        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("By payment method")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if data.isEmpty {
                Text("No data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(height: 110)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { idx, item in
                    SectorMark(
                        angle: .value("Amount", item.value),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Method", item.label))
                    .accessibilityLabel("\(item.label): \(formatMoney(item.value))")
                }
                .chartLegend(.hidden)
                .frame(height: 110)
            }
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Tile enum

public enum InvoiceStatsTile: String, Sendable {
    case outstanding, overdue, paid, avgValue

    var label: String {
        switch self {
        case .outstanding: return "Outstanding"
        case .overdue:     return "Overdue"
        case .paid:        return "Paid"
        case .avgValue:    return "Avg Value"
        }
    }
}

// MARK: - AXChartDescriptor

private struct StatusPieDescriptor: AXChartDescriptorRepresentable {
    let data: [(label: String, value: Double, color: Color)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(
            name: "Invoice status",
            isContinuous: false,
            dataPoints: data.map { item in
                AXDataPoint(x: item.label, y: item.value)
            }
        )
        return AXChartDescriptor(
            title: "Invoices by status",
            summary: "Pie chart of outstanding, paid, and overdue invoice amounts",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Status", categoryOrder: data.map(\.label)),
            yAxis: AXNumericDataAxisDescriptor(title: "Amount (USD)", range: 0...Double(data.map(\.value).max() ?? 1), gridlinePositions: []) { v in "$\(Int(v))" },
            series: [series]
        )
    }
}
#endif
