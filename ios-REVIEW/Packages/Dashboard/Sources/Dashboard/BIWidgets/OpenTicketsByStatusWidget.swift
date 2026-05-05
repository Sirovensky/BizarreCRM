import SwiftUI
import Charts
import Observation
import DesignSystem

// MARK: - OpenTicketsByStatusWidget
//
// Donut chart of ticket counts by status.
// Source: GET /api/v1/reports/dashboard → data.status_counts[]
// (reports.routes.ts line 167)

// MARK: - ViewModel

@MainActor
@Observable
public final class OpenTicketsByStatusViewModel {
    public let title = "Tickets by Status"
    public private(set) var state: BIWidgetState<[TicketStatusCount]> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchDashboardSummary()
            let active = payload.statusCounts.filter { $0.count > 0 }
            state = .loaded(active)
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

public struct OpenTicketsByStatusWidget: View, BIWidgetView {
    public let widgetTitle = "Tickets by Status"
    @State private var vm: OpenTicketsByStatusViewModel

    public init(vm: OpenTicketsByStatusViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "chart.pie") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let statuses):
                if statuses.isEmpty {
                    BIWidgetEmptyState(message: "No open tickets.")
                } else {
                    DonutWithLegend(statuses: statuses)
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

// MARK: - DonutWithLegend

private struct DonutWithLegend: View {
    let statuses: [TicketStatusCount]

    private var total: Int { statuses.reduce(0) { $0 + $1.count } }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Donut — chart content, no glass
            ZStack {
                Chart(statuses) { status in
                    SectorMark(
                        angle: .value("Count", status.count),
                        innerRadius: .ratio(0.60),
                        angularInset: 1.5
                    )
                    .foregroundStyle(color(for: status))
                    .cornerRadius(3)
                }
                .frame(width: 90, height: 90)

                VStack(spacing: 0) {
                    Text("\(total)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text("total")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .accessibilityLabel("Donut chart: \(total) total tickets")

            // Legend
            VStack(alignment: .leading, spacing: 5) {
                ForEach(statuses.prefix(6)) { status in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: status))
                            .frame(width: 7, height: 7)
                        Text(status.name)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(status.count)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.name)
                    .accessibilityValue("\(status.count)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for status: TicketStatusCount) -> Color {
        if let hex = status.color, let c = Color(hex: hex) { return c }
        let palette: [Color] = [
            .bizarreOrange, .bizarreOrange.opacity(0.7),
            Color(.systemBlue), Color(.systemGreen),
            Color(.systemPurple), Color(.systemYellow),
        ]
        return palette[status.id % palette.count]
    }
}

// MARK: - Color(hex:) helper

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6 || h.count == 8 else { return nil }
        if h.count == 6 { h = "FF" + h }
        guard let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255,
            opacity: Double((val >> 24) & 0xFF) / 255
        )
    }
}
