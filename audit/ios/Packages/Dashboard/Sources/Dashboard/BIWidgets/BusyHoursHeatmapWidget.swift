import SwiftUI
import Charts
import Observation
import DesignSystem

// MARK: - BusyHoursHeatmapWidget
//
// §3.2 Busy Hours heatmap — ticket volume × hour-of-day × day-of-week.
// Source: GET /api/v1/reports/busy-hours
// Uses SwiftUI Charts RectangleMark for a color-intensity grid.

// MARK: - ViewModel

@MainActor
@Observable
public final class BusyHoursViewModel {
    public let title = "Busy Hours"
    public private(set) var state: BIWidgetState<BusyHoursPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchBusyHours()
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

public struct BusyHoursHeatmapWidget: View, BIWidgetView {
    public let widgetTitle = "Busy Hours"
    @State private var vm: BusyHoursViewModel

    public init(vm: BusyHoursViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "calendar.badge.clock") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                BusyHoursContent(data: data)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Content

private struct BusyHoursContent: View {
    let data: BusyHoursPayload

    // Day names short, starting Monday (ISO week convention for shops)
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // Business-relevant hours to show: 7am–9pm
    private let visibleHours = Array(7...21)

    private var maxCount: Int {
        data.cells.map { $0.ticketCount }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.cells.isEmpty {
                Text("No data yet")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                Chart(data.cells) { cell in
                    // Only render visible hours
                    if visibleHours.contains(cell.hour) {
                        RectangleMark(
                            x: .value("Hour", cell.hour),
                            y: .value("Day", dayNames[safe: cell.dayOfWeek] ?? "")
                        )
                        .foregroundStyle(
                            by: .value("Tickets", cell.ticketCount)
                        )
                        .cornerRadius(2)
                    }
                }
                .chartForegroundStyleScale(range: [
                    Color.bizarreOrange.opacity(0.05),
                    Color.bizarreOrange.opacity(0.9)
                ])
                .chartXAxis {
                    AxisMarks(values: visibleHours.filter { $0 % 3 == 0 }) { v in
                        if let h = v.as(Int.self) {
                            AxisValueLabel {
                                Text(hourLabel(h))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        if let label = v.as(String.self) {
                            AxisValueLabel {
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                }
                .frame(height: 110)
                .accessibilityLabel("Busy hours heatmap: ticket volume by hour and day of week.")
            }
        }
        .padding(12)
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
