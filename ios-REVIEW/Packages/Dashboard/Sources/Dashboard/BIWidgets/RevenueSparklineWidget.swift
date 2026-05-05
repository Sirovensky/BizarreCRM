import SwiftUI
import Charts
import Observation
import Networking
import DesignSystem

// MARK: - RevenueSparklineWidget
//
// Revenue sparkline sourced from GET /api/v1/reports/dashboard → data.revenue_trend
// (12-month rolling window). Uses Swift Charts LineMark + AreaMark.

// MARK: - ViewModel

@MainActor
@Observable
public final class RevenueSparklineViewModel {
    public let title = "Revenue Trend"
    public private(set) var state: BIWidgetState<[RevenueTrendPoint]> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchDashboardSummary()
            state = .loaded(payload.revenueTrend)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reload() async {
        state = .idle
        await load()
    }
}

// MARK: - View

public struct RevenueSparklineWidget: View, BIWidgetView {
    public let widgetTitle = "Revenue Trend"
    @State private var vm: RevenueSparklineViewModel

    public init(vm: RevenueSparklineViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "chart.line.uptrend.xyaxis") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let points):
                if points.isEmpty {
                    BIWidgetEmptyState(message: "No revenue data yet.")
                } else {
                    SparklineChart(points: points)
                }
            case .failed(let msg):
                BIWidgetErrorState(message: msg) {
                    Task { await vm.reload() }
                }
            }
        }
        .task { await vm.load() }
        .accessibilityLabel(widgetTitle)
    }
}

// MARK: - SparklineChart (chart content — no glass)

private struct SparklineChart: View {
    let points: [RevenueTrendPoint]

    private var maxRevenue: Double {
        points.map(\.revenue).max() ?? 1
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Month", point.month),
                y: .value("Revenue", point.revenue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.bizarreOrange.opacity(0.3), Color.bizarreOrange.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Month", point.month),
                y: .value("Revenue", point.revenue)
            )
            .foregroundStyle(Color.bizarreOrange)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... (maxRevenue * 1.15))
        .frame(height: 80)
        .accessibilityLabel("Revenue sparkline for last 12 months")
        .accessibilityValue(
            points.last.map { "Latest: \(currencyString($0.revenue))" } ?? "No data"
        )
    }

    private func currencyString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
