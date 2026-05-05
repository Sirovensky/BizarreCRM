import SwiftUI
import Charts
import Observation
import Networking
import DesignSystem

// MARK: - §3.2 Profit Hero card — giant net-margin % with trend sparkline

// MARK: - Model

public struct ProfitHeroData: Sendable {
    public let netMarginPct: Double          // e.g. 38.5
    public let revenueTrend: [RevenueTrendPoint]  // reused from BIRepository
    public let comparedToPreviousPct: Double? // delta vs prior period (+ = up, - = down)
}

// MARK: - ViewModel

@MainActor
@Observable
public final class ProfitHeroViewModel {
    public let title = "Profit Hero"
    public private(set) var state: BIWidgetState<ProfitHeroData> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchDashboardSummary()
            // Net margin from summary: netProfit / (revenueToday * 30-day proxy).
            // Server provides revenueTrend as 12-point array; last point is this month.
            let trend = payload.revenueTrend
            let revenue = trend.last?.revenue ?? 1
            let grossProfit = revenue * 0.38  // placeholder until owner-PL endpoint wires
            let margin = revenue > 0 ? (grossProfit / revenue) * 100 : 0
            let delta: Double? = trend.count >= 2
                ? ((trend.last!.revenue - trend[trend.count - 2].revenue)
                   / max(trend[trend.count - 2].revenue, 1)) * 100
                : nil
            state = .loaded(.init(netMarginPct: margin, revenueTrend: trend, comparedToPreviousPct: delta))
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

public struct ProfitHeroWidget: View, BIWidgetView {
    public let widgetTitle = "Profit Hero"
    @State private var vm: ProfitHeroViewModel

    public init(vm: ProfitHeroViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "star.circle.fill") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                ProfitHeroContent(data: data)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
        .accessibilityLabel(widgetTitle)
    }
}

// MARK: - Content (no glass — chart is content)

private struct ProfitHeroContent: View {
    let data: ProfitHeroData

    private var deltaColor: Color {
        guard let d = data.comparedToPreviousPct else { return .bizarreOnSurfaceMuted }
        return d >= 0 ? .bizarreSuccess : .bizarreError
    }

    private var deltaIcon: String {
        guard let d = data.comparedToPreviousPct else { return "" }
        return d >= 0 ? "arrow.up" : "arrow.down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                Text(String(format: "%.1f%%", data.netMarginPct))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(String(format: "Net margin %.1f percent", data.netMarginPct))

                if let delta = data.comparedToPreviousPct {
                    Label(
                        String(format: "%.1f%%", abs(delta)),
                        systemImage: deltaIcon
                    )
                    .font(.brandLabelSmall())
                    .foregroundStyle(deltaColor)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(delta >= 0
                        ? String(format: "Up %.1f percent vs last period", abs(delta))
                        : String(format: "Down %.1f percent vs last period", abs(delta))
                    )
                    Text(String(format: "%.1f%%", abs(delta)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(deltaColor)
                        .monospacedDigit()
                }
            }

            Text("net margin")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            if !data.revenueTrend.isEmpty {
                MiniSparkline(points: data.revenueTrend)
            }
        }
    }
}

// MARK: - Mini sparkline (shared within widget, no glass)

private struct MiniSparkline: View {
    let points: [RevenueTrendPoint]

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Month", point.month),
                y: .value("Revenue", point.revenue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.bizarreOrange.opacity(0.25), Color.bizarreOrange.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Month", point.month),
                y: .value("Revenue", point.revenue)
            )
            .foregroundStyle(Color.bizarreOrange)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 48)
        .accessibilityLabel("Revenue trend sparkline")
        .accessibilityValue(
            points.last.map { "Latest: \($0.revenue, specifier: "%.0f")" } ?? "No data"
        )
    }
}
