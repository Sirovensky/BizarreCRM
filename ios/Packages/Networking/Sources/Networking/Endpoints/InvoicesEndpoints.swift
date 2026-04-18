import Foundation

/// `GET /api/v1/invoices` response.
/// Server: packages/server/src/routes/invoices.routes.ts:94,147.
/// Envelope data: `{ invoices: [...], pagination: {...}, aging_summary: {...} }`.
/// Amounts are Double (dollars), NOT integer cents — inconsistent with tickets.
public struct InvoicesListResponse: Decodable, Sendable {
    public let invoices: [InvoiceSummary]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int
        public let perPage: Int
        public let total: Int
        public let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case page, total
            case perPage = "per_page"
            case totalPages = "total_pages"
        }
    }
}

public struct InvoiceSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let firstName: String?
    public let lastName: String?
    public let organization: String?
    public let customerPhone: String?
    public let ticketId: Int64?
    public let ticketOrderId: String?
    public let subtotal: Double?
    public let discount: Double?
    public let totalTax: Double?
    public let total: Double?
    public let status: String?
    public let amountPaid: Double?
    public let amountDue: Double?
    public let createdAt: String?
    public let dueOn: String?

    public var customerName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return organization?.isEmpty == false ? organization! : "—"
    }

    public var displayId: String { orderId?.isEmpty == false ? orderId! : "INV-?" }

    public enum Status: Sendable { case paid, unpaid, partial, void_, other }

    public var statusKind: Status {
        switch status?.lowercased() {
        case "paid":    return .paid
        case "unpaid":  return .unpaid
        case "partial": return .partial
        case "void":    return .void_
        default:        return .other
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, organization, subtotal, discount, total, status
        case orderId = "order_id"
        case customerId = "customer_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case customerPhone = "customer_phone"
        case ticketId = "ticket_id"
        case ticketOrderId = "ticket_order_id"
        case totalTax = "total_tax"
        case amountPaid = "amount_paid"
        case amountDue = "amount_due"
        case createdAt = "created_at"
        case dueOn = "due_on"
    }
}

public enum InvoiceFilter: String, CaseIterable, Sendable, Identifiable {
    case all, paid, unpaid, partial, overdue

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:     return "All"
        case .paid:    return "Paid"
        case .unpaid:  return "Unpaid"
        case .partial: return "Partial"
        case .overdue: return "Overdue"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .all:     return []
        case .paid:    return [URLQueryItem(name: "status", value: "paid")]
        case .unpaid:  return [URLQueryItem(name: "status", value: "unpaid")]
        case .partial: return [URLQueryItem(name: "status", value: "partial")]
        case .overdue: return [URLQueryItem(name: "status", value: "overdue")]
        }
    }
}

public extension APIClient {
    func listInvoices(filter: InvoiceFilter = .all, keyword: String? = nil, pageSize: Int = 50) async throws -> InvoicesListResponse {
        var items = filter.queryItems
        items.append(URLQueryItem(name: "pagesize", value: String(pageSize)))
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/invoices", query: items, as: InvoicesListResponse.self)
    }
}
