import Foundation
import Observation
import Networking
import Core

// MARK: - Period

public enum FinancialPeriod: String, CaseIterable, Sendable {
    case thisMonth  = "This Month"
    case lastMonth  = "Last Month"
    case thisQuarter = "This Quarter"
    case thisYear   = "This Year"
    case last12Months = "Last 12 Months"

    public func dateRange(calendar: Calendar = .current) -> (from: Date, to: Date) {
        let now = Date()
        switch self {
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return (start, end)
        case .lastMonth:
            let thisStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let start = calendar.date(byAdding: .month, value: -1, to: thisStart)!
            let end = calendar.date(byAdding: .day, value: -1, to: thisStart)!
            return (start, end)
        case .thisQuarter:
            let month = calendar.component(.month, from: now)
            let qStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = qStartMonth
            comps.day = 1
            let start = calendar.date(from: comps)!
            let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start)!
            return (start, end)
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start)!
            return (start, end)
        case .last12Months:
            let end = now
            let start = calendar.date(byAdding: .month, value: -12, to: end)!
            return (start, end)
        }
    }
}

// MARK: - FinancialDashboardViewModel

@MainActor
@Observable
public final class FinancialDashboardViewModel {

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded(FinancialDashboardData)
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public var period: FinancialPeriod = .thisMonth
    public var isAccessDenied: Bool = false

    @ObservationIgnored private let api: APIClient

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public init(api: APIClient) {
        self.api = api
    }

    public func load(roleCapabilities: Set<String> = []) async {
        guard FinancialDashboardAccessControl.canAccess(roleCapabilities: roleCapabilities) ||
              roleCapabilities.isEmpty  // allow when no role context is provided (offline)
        else {
            isAccessDenied = true
            return
        }

        loadState = .loading
        let range = period.dateRange()
        let from = Self.dateFormatter.string(from: range.from)
        let to   = Self.dateFormatter.string(from: range.to)

        do {
            async let pnlTask    = api.getFinancePnL(from: from, to: to)
            async let flowTask   = api.getFinanceCashFlow(from: from, to: to)
            async let agingTask  = api.getFinanceAging()
            async let custTask   = api.getFinanceTopCustomers(from: from, to: to)
            async let skuTask    = api.getFinanceTopSkus(from: from, to: to)

            let (pnlResp, flowResp, agingResp, custResp, skuResp) =
                try await (pnlTask, flowTask, agingTask, custTask, skuTask)

            let pnl = PnLSnapshot(
                revenueCents: pnlResp.revenueCents,
                cogsCents: pnlResp.cogsCents,
                expensesCents: pnlResp.expensesCents
            )

            let cashFlow = flowResp.map { p in
                CashFlowPoint(
                    id: p.date,
                    date: Self.dateFormatter.date(from: p.date) ?? .distantPast,
                    inflowCents: p.inflowCents,
                    outflowCents: p.outflowCents
                )
            }

            let agingBuckets = agingResp.buckets
            let aging = AgedReceivablesSnapshot(
                current:    bucketFrom(agingBuckets, label: "0-30"),
                thirtyPlus: bucketFrom(agingBuckets, label: "31-60"),
                sixtyPlus:  bucketFrom(agingBuckets, label: "61-90"),
                ninetyPlus: bucketFrom(agingBuckets, label: "90+")
            )

            let topCustomers = custResp.map {
                TopCustomer(id: $0.id, name: $0.name, revenueCents: $0.revenueCents)
            }

            let topSkus = skuResp.map {
                TopSkuByMargin(id: $0.id, sku: $0.sku, name: $0.name,
                               marginCents: $0.marginCents, marginPct: $0.marginPct)
            }

            loadState = .loaded(FinancialDashboardData(
                pnl: pnl,
                cashFlow: cashFlow,
                agedReceivables: aging,
                topCustomers: topCustomers,
                topSkus: topSkus
            ))
        } catch {
            AppLog.ui.error("FinancialDashboard load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Private

    private func bucketFrom(_ buckets: [FinanceAgingBucket], label: String) -> AgedReceivablesBucket {
        let match = buckets.first { $0.label == label }
        return AgedReceivablesBucket(
            label: label,
            totalCents: match?.totalCents ?? 0,
            invoiceCount: match?.invoiceCount ?? 0
        )
    }
}
