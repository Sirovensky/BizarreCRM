import SwiftUI
import Charts
import Observation
import DesignSystem

// MARK: - §3.2 Repeat-Customers card — repeat-rate %
//
// Displays the percentage of customers who returned for more than one visit
// in the selected date range.
//
// Server endpoint: GET /api/v1/reports/repeat-customers
// Payload reuses `RepeatCustomersPayload` (DashboardBIRepository.swift line 202).

// MARK: - ViewModel

@MainActor
@Observable
public final class RepeatCustomersViewModel {
    public let title = "Repeat Customers"
    public private(set) var state: BIWidgetState<RepeatCustomersPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchTopCustomers()
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

public struct RepeatCustomersWidget: View, BIWidgetView {
    public let widgetTitle = "Repeat Customers"
    @State private var vm: RepeatCustomersViewModel

    public init(vm: RepeatCustomersViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let payload):
                loadedContent(payload: payload)
            case .failed(let msg):
                BIWidgetErrorState(message: msg, retry: { Task { await vm.reload() } })
            }
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func loadedContent(payload: RepeatCustomersPayload) -> some View {
        let rate = repeatRate(from: payload)
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Big rate %
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f%%", rate))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .accessibilityLabel("Repeat customer rate: \(String(format: "%.0f", rate)) percent")
                Text("return rate")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Mini donut chart (Charts) — repeat vs new split
            if !payload.top.isEmpty {
                Chart {
                    SectorMark(
                        angle: .value("Repeat", rate),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityLabel("Repeat: \(String(format: "%.0f", rate)) percent")

                    SectorMark(
                        angle: .value("New", max(100 - rate, 0)),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                    .accessibilityLabel("New: \(String(format: "%.0f", max(100 - rate, 0))) percent")
                }
                .frame(height: 80)
                .chartLegend(.hidden)
            }

            // Footer: top revenue share
            Text(String(format: "Top customers: %.0f%% of revenue", payload.combinedSharePct * 100))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    /// Derive repeat rate from payload.
    /// `combinedSharePct` is the top customers' combined share of total revenue (0–1 scale).
    /// Repeat-rate ≈ percentage of top-list entries with >1 ticket (multiple visits).
    private func repeatRate(from payload: RepeatCustomersPayload) -> Double {
        guard !payload.top.isEmpty else { return 0 }
        let repeatCount = payload.top.filter { $0.ticketCount > 1 }.count
        return (Double(repeatCount) / Double(payload.top.count)) * 100
    }
}
