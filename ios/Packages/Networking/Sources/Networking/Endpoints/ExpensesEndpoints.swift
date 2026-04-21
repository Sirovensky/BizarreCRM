import Foundation

/// `GET /api/v1/expenses`.
/// Envelope: `{ expenses: [...], summary: {...}, categories: [...], pagination: {...} }`.
/// We expose `expenses` + `summary` at MVP; `categories` is for chart
/// screens (not wired yet).
public struct ExpensesListResponse: Decodable, Sendable {
    public let expenses: [Expense]
    public let summary: Summary?

    public struct Summary: Decodable, Sendable {
        public let totalAmount: Double
        public let totalCount: Int

        enum CodingKeys: String, CodingKey {
            case totalAmount = "total_amount"
            case totalCount = "total_count"
        }
    }
}

public struct Expense: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let category: String?
    public let amount: Double?
    public let description: String?
    public let date: String?
    public let receiptPath: String?
    public let userId: Int64?
    public let firstName: String?
    public let lastName: String?
    public let createdAt: String?
    public let updatedAt: String?

    public var createdByName: String? {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, category, amount, description, date
        case receiptPath = "receipt_path"
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension APIClient {
    func listExpenses(keyword: String? = nil, category: String? = nil,
                      fromDate: String? = nil, toDate: String? = nil,
                      pageSize: Int = 50) async throws -> ExpensesListResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let c = category { items.append(URLQueryItem(name: "category", value: c)) }
        if let f = fromDate { items.append(URLQueryItem(name: "from_date", value: f)) }
        if let t = toDate { items.append(URLQueryItem(name: "to_date", value: t)) }
        return try await get("/api/v1/expenses", query: items, as: ExpensesListResponse.self)
    }

    /// `GET /api/v1/expenses/:id` — single expense with user name fields.
    func getExpense(id: Int64) async throws -> Expense {
        try await get("/api/v1/expenses/\(id)", as: Expense.self)
    }
}
