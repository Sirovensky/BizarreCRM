import Foundation

/// `GET /api/v1/invoices/:id` response (unwrapped).
/// Server: packages/server/src/routes/invoices.routes.ts:27–64,193.
/// Root fields are flat — customer info is JOINed inline (no nested object).
public struct InvoiceDetail: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let ticketId: Int64?
    public let firstName: String?
    public let lastName: String?
    public let customerEmail: String?
    public let customerPhone: String?
    public let organization: String?
    public let subtotal: Double?
    public let discount: Double?
    public let discountReason: String?
    public let totalTax: Double?
    public let total: Double?
    public let status: String?
    public let amountPaid: Double?
    public let amountDue: Double?
    public let notes: String?
    public let dueOn: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let createdByName: String?
    public let lineItems: [LineItem]?
    public let payments: [Payment]?

    public var customerDisplayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let org = organization, !org.isEmpty { return org }
        return "—"
    }

    public struct LineItem: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let invoiceId: Int64?
        public let inventoryItemId: Int64?
        public let description: String?
        public let itemName: String?
        public let sku: String?
        public let quantity: Double?
        public let unitPrice: Double?
        public let lineDiscount: Double?
        public let taxAmount: Double?
        public let total: Double?

        public var displayName: String {
            if let n = itemName, !n.isEmpty { return n }
            if let d = description, !d.isEmpty { return d }
            return "Item"
        }

        enum CodingKeys: String, CodingKey {
            case id, description, quantity, sku, total
            case invoiceId = "invoice_id"
            case inventoryItemId = "inventory_item_id"
            case itemName = "item_name"
            case unitPrice = "unit_price"
            case lineDiscount = "line_discount"
            case taxAmount = "tax_amount"
        }
    }

    public struct Payment: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let amount: Double?
        public let method: String?
        public let methodDetail: String?
        public let transactionId: String?
        public let notes: String?
        public let paymentType: String?
        public let createdAt: String?
        public let recordedBy: String?

        enum CodingKeys: String, CodingKey {
            case id, amount, method, notes
            case methodDetail = "method_detail"
            case transactionId = "transaction_id"
            case paymentType = "payment_type"
            case createdAt = "created_at"
            case recordedBy = "recorded_by"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, subtotal, discount, total, status, notes, organization
        case orderId = "order_id"
        case customerId = "customer_id"
        case ticketId = "ticket_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case customerEmail = "customer_email"
        case customerPhone = "customer_phone"
        case discountReason = "discount_reason"
        case totalTax = "total_tax"
        case amountPaid = "amount_paid"
        case amountDue = "amount_due"
        case dueOn = "due_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdByName = "created_by_name"
        case lineItems = "line_items"
        case payments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
        customerId = try c.decodeIfPresent(Int64.self, forKey: .customerId)
        ticketId = try c.decodeIfPresent(Int64.self, forKey: .ticketId)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        customerEmail = try c.decodeIfPresent(String.self, forKey: .customerEmail)
        customerPhone = try c.decodeIfPresent(String.self, forKey: .customerPhone)
        organization = try c.decodeIfPresent(String.self, forKey: .organization)
        subtotal = try c.decodeIfPresent(Double.self, forKey: .subtotal)
        discount = try c.decodeIfPresent(Double.self, forKey: .discount)
        discountReason = try c.decodeIfPresent(String.self, forKey: .discountReason)
        totalTax = try c.decodeIfPresent(Double.self, forKey: .totalTax)
        total = try c.decodeIfPresent(Double.self, forKey: .total)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        amountPaid = try c.decodeIfPresent(Double.self, forKey: .amountPaid)
        amountDue = try c.decodeIfPresent(Double.self, forKey: .amountDue)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        dueOn = try c.decodeIfPresent(String.self, forKey: .dueOn)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        createdByName = try c.decodeIfPresent(String.self, forKey: .createdByName)
        lineItems = try c.decodeIfPresent([LineItem].self, forKey: .lineItems)
        payments = try c.decodeIfPresent([Payment].self, forKey: .payments)
    }
}

// MARK: - Status-gating helpers (§7 toolbar actions)

public extension InvoiceDetail {
    /// Invoice can accept a payment when it is not fully paid or void.
    var canPay: Bool {
        let s = (status ?? "").lowercased()
        guard s != "paid" && s != "void" else { return false }
        return (amountDue ?? 0) > 0
    }

    /// Invoice can be refunded when it has payments.
    var canRefund: Bool {
        guard (status ?? "").lowercased() != "void" else { return false }
        return (amountPaid ?? 0) > 0
    }

    /// Invoice can be voided when status is draft, or it has no payments.
    var canVoid: Bool {
        let s = (status ?? "").lowercased()
        if s == "void" || s == "paid" { return false }
        return (amountPaid ?? 0) == 0 || s == "draft"
    }
}

public extension APIClient {
    func invoice(id: Int64) async throws -> InvoiceDetail {
        try await get("/api/v1/invoices/\(id)", as: InvoiceDetail.self)
    }

    // §7.2 Clone invoice — POST /api/v1/invoices/:id/clone
    // Server duplicates all line items, sets status to "draft", returns new invoice id.
    func cloneInvoice(id: Int64) async throws -> CloneInvoiceResponse {
        try await post("/api/v1/invoices/\(id)/clone", body: InvoiceCloneEmptyBody(), as: CloneInvoiceResponse.self)
    }
}

public struct CloneInvoiceResponse: Decodable, Sendable {
    public let id: Int64
    public let orderId: String?
    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
    }
}

// Empty body for POST requests that require no payload (named to avoid conflict with NotificationsEndpoints.EmptyBody)
private struct InvoiceCloneEmptyBody: Encodable, Sendable {}

// MARK: - Void endpoint
// Server: POST /api/v1/invoices/:id/void
// Allowed transitions: any non-void status with no payments (or draft)

public struct InvoiceVoidRequest: Encodable, Sendable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

public struct InvoiceVoidResponse: Decodable, Sendable {
    public let message: String?
    enum CodingKeys: String, CodingKey { case message }
}

public extension APIClient {
    /// `POST /api/v1/invoices/:id/void`
    func voidInvoice(id: Int64, reason: String) async throws -> InvoiceVoidResponse {
        try await post("/api/v1/invoices/\(id)/void",
                       body: InvoiceVoidRequest(reason: reason),
                       as: InvoiceVoidResponse.self)
    }
}

// MARK: - Email receipt endpoint
// Server: POST /api/v1/invoices/:id/email-receipt

public struct EmailReceiptBody: Encodable, Sendable {
    public let email: String
    public let message: String?
    public init(email: String, message: String? = nil) {
        self.email = email
        self.message = message
    }
}

public struct EmailReceiptApiResponse: Decodable, Sendable {
    public let success: Bool?
}

public extension APIClient {
    /// `POST /api/v1/invoices/:id/email-receipt`
    func emailReceipt(invoiceId: Int64, body: EmailReceiptBody) async throws -> EmailReceiptApiResponse {
        try await post("/api/v1/invoices/\(invoiceId)/email-receipt",
                       body: body,
                       as: EmailReceiptApiResponse.self)
    }
}
