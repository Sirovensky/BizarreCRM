import Foundation
import Networking

// MARK: - Finance API response wrappers

public struct FinancePnLResponse: Decodable, Sendable {
    public let revenueCents: Int
    public let cogsCents: Int
    public let expensesCents: Int

    enum CodingKeys: String, CodingKey {
        case revenueCents  = "revenue_cents"
        case cogsCents     = "cogs_cents"
        case expensesCents = "expenses_cents"
    }
}

public struct FinanceCashFlowPoint: Decodable, Sendable {
    public let date: String
    public let inflowCents: Int
    public let outflowCents: Int

    enum CodingKeys: String, CodingKey {
        case date
        case inflowCents  = "inflow_cents"
        case outflowCents = "outflow_cents"
    }
}

public struct FinanceAgingBucket: Decodable, Sendable {
    public let label: String
    public let totalCents: Int
    public let invoiceCount: Int

    enum CodingKeys: String, CodingKey {
        case label
        case totalCents    = "total_cents"
        case invoiceCount  = "invoice_count"
    }
}

public struct FinanceAgingResponse: Decodable, Sendable {
    public let buckets: [FinanceAgingBucket]
}

public struct FinanceTopCustomer: Decodable, Sendable {
    public let id: String
    public let name: String
    public let revenueCents: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case revenueCents = "revenue_cents"
    }
}

public struct FinanceTopSku: Decodable, Sendable {
    public let id: String
    public let sku: String
    public let name: String
    public let marginCents: Int
    public let marginPct: Double

    enum CodingKeys: String, CodingKey {
        case id
        case sku
        case name
        case marginCents = "margin_cents"
        case marginPct   = "margin_pct"
    }
}

// §59/§15 expense category drilldown — server response model
public struct FinanceExpenseCategory: Decodable, Sendable {
    public let category: String
    public let amountCents: Int
    public let shareOfTotal: Double

    enum CodingKeys: String, CodingKey {
        case category
        case amountCents   = "amount_cents"
        case shareOfTotal  = "share_of_total"
    }
}

// MARK: - APIClient + Finance endpoints

public extension APIClient {

    func getFinancePnL(from: String, to: String) async throws -> FinancePnLResponse {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await get("/api/v1/finance/pnl", query: query, as: FinancePnLResponse.self)
    }

    func getFinanceCashFlow(from: String, to: String, groupBy: String = "day") async throws -> [FinanceCashFlowPoint] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "groupBy", value: groupBy)
        ]
        return try await get("/api/v1/finance/cashflow", query: query, as: [FinanceCashFlowPoint].self)
    }

    func getFinanceAging() async throws -> FinanceAgingResponse {
        try await get("/api/v1/finance/aging", as: FinanceAgingResponse.self)
    }

    func getFinanceTopCustomers(from: String, to: String, limit: Int = 10) async throws -> [FinanceTopCustomer] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/v1/finance/top-customers", query: query, as: [FinanceTopCustomer].self)
    }

    func getFinanceTopSkus(from: String, to: String, limit: Int = 10) async throws -> [FinanceTopSku] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/v1/finance/top-skus", query: query, as: [FinanceTopSku].self)
    }

    // §59/§15 expense category drilldown — GET /api/v1/finance/expenses-by-category
    func getFinanceExpensesByCategory(from: String, to: String) async throws -> [FinanceExpenseCategory] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await get("/api/v1/finance/expenses-by-category", query: query,
                             as: [FinanceExpenseCategory].self)
    }

    func getFinanceTaxYear(year: Int) async throws -> FinancePnLResponse {
        let query: [URLQueryItem] = [URLQueryItem(name: "year", value: String(year))]
        return try await get("/api/v1/finance/tax-year", query: query, as: FinancePnLResponse.self)
    }
}
