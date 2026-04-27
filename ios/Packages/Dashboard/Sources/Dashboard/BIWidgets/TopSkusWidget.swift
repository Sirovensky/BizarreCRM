import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - TopSkusWidget
//
// Top services sourced from:
//   GET /api/v1/reports/dashboard → data.top_services[]
//   Server shape: { name, count, revenue }  (reports.routes.ts line ~194)

// MARK: - ViewModel
// TopServiceEntry and DashboardTopServicesPayload live in Networking/DashboardEndpoints.swift (§20)

@MainActor
@Observable
public final class TopSkusViewModel {
    public let title = "Top Services"
    public private(set) var state: BIWidgetState<[TopServiceEntry]> = .idle

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            // Uses APIClient.dashboardTopServices() (§20 containment — DashboardEndpoints.swift)
            let entries = try await api.dashboardTopServices()
            state = .loaded(entries)
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

public struct TopSkusWidget: View, BIWidgetView {
    public let widgetTitle = "Top Services"
    @State private var vm: TopSkusViewModel

    public init(vm: TopSkusViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "wrench.and.screwdriver") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let entries):
                if entries.isEmpty {
                    BIWidgetEmptyState(message: "No service data for the last 12 months.")
                } else {
                    SkuList(entries: entries)
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

// MARK: - SkuList

private struct SkuList: View {
    let entries: [TopServiceEntry]

    var body: some View {
        let maxRevenue = entries.map(\.revenue).max() ?? 1
        VStack(spacing: 8) {
            ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { idx, entry in
                SkuRow(entry: entry, maxRevenue: maxRevenue, rank: idx + 1)
            }
        }
    }
}

private struct SkuRow: View {
    let entry: TopServiceEntry
    let maxRevenue: Double
    let rank: Int

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private var revenueString: String {
        Self.currencyFormatter.string(from: NSNumber(value: entry.revenue)) ?? "$\(Int(entry.revenue))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(rank)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 16, alignment: .trailing)
                    .monospacedDigit()
                Text(entry.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(revenueString)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                let width = geo.size.width * (entry.revenue / maxRevenue)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.bizarreOrange.opacity(0.6))
                    .frame(width: max(4, width), height: 3)
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(entry.name)")
        .accessibilityValue("\(revenueString), \(entry.count) tickets")
    }
}
