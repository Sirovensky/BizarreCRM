import SwiftUI
import Observation
import DesignSystem

// MARK: - TopCustomersWidget
//
// Top repeat customers from GET /api/v1/reports/repeat-customers
// (reports.routes.ts line 2245)

// MARK: - ViewModel

@MainActor
@Observable
public final class TopCustomersViewModel {
    public let title = "Top Customers"
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

public struct TopCustomersWidget: View, BIWidgetView {
    public let widgetTitle = "Top Customers"
    @State private var vm: TopCustomersViewModel

    public init(vm: TopCustomersViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "person.3") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let payload):
                if payload.top.isEmpty {
                    BIWidgetEmptyState(message: "No repeat customers yet.")
                } else {
                    CustomerList(payload: payload)
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

// MARK: - CustomerList

private struct CustomerList: View {
    let payload: RepeatCustomersPayload

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(payload.top.prefix(5).enumerated()), id: \.element.id) { idx, customer in
                CustomerRow(customer: customer, rank: idx + 1, formatter: Self.currencyFormatter)
                if idx < min(4, payload.top.count - 1) {
                    Divider().overlay(Color.bizarreOutline.opacity(0.2))
                }
            }
            if payload.combinedSharePct > 0 {
                Divider().overlay(Color.bizarreOutline.opacity(0.2)).padding(.top, 6)
                HStack {
                    Text("Top 5 share")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer(minLength: 4)
                    Text(String(format: "%.1f%%", payload.combinedSharePct))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(.top, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Top 5 share of total revenue")
                .accessibilityValue(String(format: "%.1f%%", payload.combinedSharePct))
            }
        }
    }
}

private struct CustomerRow: View {
    let customer: TopCustomerEntry
    let rank: Int
    let formatter: NumberFormatter

    private var spentString: String {
        formatter.string(from: NSNumber(value: customer.totalSpent)) ?? "$\(Int(customer.totalSpent))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 16, alignment: .trailing)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text("\(customer.ticketCount) tickets")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(spentString)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if customer.sharePct > 0 {
                    Text(String(format: "%.1f%%", customer.sharePct))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(customer.name)")
        .accessibilityValue("\(spentString) lifetime, \(customer.ticketCount) tickets")
    }
}
