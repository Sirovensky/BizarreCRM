import Foundation

/// `GET /api/v1/invoices` response.
/// Server: packages/server/src/routes/invoices.routes.ts:94,147.
/// Envelope data: `{ invoices: [...], pagination: {...}, aging_summary: {...} }`.
/// Amounts are Double (dollars), NOT integer cents — inconsistent with tickets.
public struct InvoicesListResponse: Decodable, Sendable {
    public let invoices: [InvoiceSummary]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

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

// MARK: - Payment recording
// Server: POST /api/v1/invoices/:id/payments
// Requires: Idempotency-Key header (injected by APIClient middleware)

public struct RecordInvoicePaymentRequest: Encodable, Sendable {
    public let amount: Double
    public let method: String
    public let methodDetail: String?
    public let transactionId: String?
    public let notes: String?
    public let paymentType: String

    public init(
        amount: Double,
        method: String,
        methodDetail: String? = nil,
        transactionId: String? = nil,
        notes: String? = nil,
        paymentType: String = "payment"
    ) {
        self.amount = amount
        self.method = method
        self.methodDetail = methodDetail
        self.transactionId = transactionId
        self.notes = notes
        self.paymentType = paymentType
    }

    enum CodingKeys: String, CodingKey {
        case amount, method, notes
        case methodDetail   = "method_detail"
        case transactionId  = "transaction_id"
        case paymentType    = "payment_type"
    }
}

/// Envelope around the full updated invoice returned by POST /invoices/:id/payments.
/// Server wraps the full invoice detail (same shape as GET /invoices/:id) in success.data.
public struct RecordPaymentResponse: Decodable, Sendable {
    public let id: Int64
    public let status: String?
    public let amountPaid: Double?
    public let amountDue: Double?

    enum CodingKeys: String, CodingKey {
        case id, status
        case amountPaid = "amount_paid"
        case amountDue  = "amount_due"
    }
}

public extension APIClient {
    /// `POST /api/v1/invoices/:id/payments`
    /// Returns the updated invoice detail. Idempotency-Key must be set per request.
    func recordPayment(invoiceId: Int64, body: RecordInvoicePaymentRequest) async throws -> RecordPaymentResponse {
        try await post("/api/v1/invoices/\(invoiceId)/payments", body: body, as: RecordPaymentResponse.self)
    }
}

// MARK: - Refund creation
// Server: POST /api/v1/refunds
// Role required: admin or manager (refunds.create permission)

public struct CreateRefundRequest: Encodable, Sendable {
    public let invoiceId: Int64?
    public let customerId: Int64
    public let amount: Double
    public let type: String
    public let reason: String?
    public let method: String?

    public init(
        invoiceId: Int64?,
        customerId: Int64,
        amount: Double,
        type: String = "refund",
        reason: String? = nil,
        method: String? = nil
    ) {
        self.invoiceId = invoiceId
        self.customerId = customerId
        self.amount = amount
        self.type = type
        self.reason = reason
        self.method = method
    }

    enum CodingKeys: String, CodingKey {
        case amount, type, reason, method
        case invoiceId  = "invoice_id"
        case customerId = "customer_id"
    }
}

public struct CreateRefundResponse: Decodable, Sendable {
    public let id: Int64

    enum CodingKeys: String, CodingKey {
        case id
    }
}

public extension APIClient {
    /// `POST /api/v1/refunds`
    /// Creates a pending refund. Separate approval step required: PATCH /api/v1/refunds/:id/approve
    func createRefund(body: CreateRefundRequest) async throws -> CreateRefundResponse {
        try await post("/api/v1/refunds", body: body, as: CreateRefundResponse.self)
    }
}
