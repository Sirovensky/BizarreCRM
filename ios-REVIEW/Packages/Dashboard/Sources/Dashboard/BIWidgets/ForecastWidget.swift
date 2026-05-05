import SwiftUI
import Charts
import Observation
import DesignSystem

// MARK: - ForecastWidget
//
// §3.2 Forecast chart — projected revenue (LineMark with confidence band).
// Source: GET /api/v1/reports/forecast

// MARK: - ViewModel

@MainActor
@Observable
public final class ForecastViewModel {
    public let title = "Revenue Forecast"
    public private(set) var state: BIWidgetState<ForecastPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchForecast()
            state = .loaded(payload)
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

public struct ForecastWidget: View, BIWidgetView {
    public let widgetTitle = "Revenue Forecast"
    @State private var vm: ForecastViewModel

    public init(vm: ForecastViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "chart.line.uptrend.xyaxis") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                ForecastContent(data: data)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Content

private struct ForecastContent: View {
    let data: ForecastPayload

    private static let moneyFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func formatMoney(_ v: Double) -> String {
        Self.moneyFmt.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    // Next projected month if any
    private var nextForecastPoint: ForecastPoint? {
        data.series.first(where: { !$0.isActual })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let next = nextForecastPoint {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatMoney(next.projected))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text("projected next month")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            if data.series.isEmpty {
                Text("Not enough data for forecast")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                Chart {
                    // Confidence band (lower–upper) for forecast points
                    ForEach(data.series.filter { !$0.isActual }) { point in
                        AreaMark(
                            x: .value("Month", point.date),
                            yStart: .value("Lower", point.lower),
                            yEnd: .value("Upper", point.upper)
                        )
                        .foregroundStyle(Color.bizarreOrange.opacity(0.15))
                        .interpolationMethod(.catmullRom)
                    }

                    // Actual historical line (solid)
                    ForEach(data.series.filter { $0.isActual }) { point in
                        LineMark(
                            x: .value("Month", point.date),
                            y: .value("Revenue", point.projected)
                        )
                        .foregroundStyle(Color.bizarreOrange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }

                    // Projected future line (dashed)
                    ForEach(data.series.filter { !$0.isActual }) { point in
                        LineMark(
                            x: .value("Month", point.date),
                            y: .value("Projected", point.projected)
                        )
                        .foregroundStyle(Color.bizarreOrange.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        if let d = v.as(Double.self) {
                            AxisValueLabel {
                                Text(formatMoney(d))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                }
                .frame(height: 100)
                .accessibilityLabel("Revenue forecast chart showing actual and projected monthly revenue.")
            }

            // Legend
            HStack(spacing: 12) {
                Label("Actual", systemImage: "minus")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                Label("Projected", systemImage: "line.diagonal")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange.opacity(0.7))
            }
        }
        .padding(12)
    }
}
