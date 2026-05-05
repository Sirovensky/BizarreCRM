import Foundation

/// §16.9 — DTOs for the POS returns / refund endpoints.
///
/// Status as of writing: `POST /api/v1/pos/returns` is scheduled but not
/// live on every deployment; `POST /api/v1/refunds/credits/:customerId`
/// ships store-credit refunds today on most tenants. The POS UI tries the
/// "full" returns endpoint first, falls back to store-credit when the
/// tenant's server does not yet expose the returns surface, and finally
/// surfaces a typed "Coming soon" error.

public struct PosReturnLineRequest: Encodable, Sendable {
    public let invoiceLineId: Int64?
    public let description: String
    public let quantity: Int
    public let unitPriceCents: Int

    public init(invoiceLineId: Int64?, description: String, quantity: Int, unitPriceCents: Int) {
        self.invoiceLineId = invoiceLineId
        self.description = description
        self.quantity = max(1, quantity)
        self.unitPriceCents = max(0, unitPriceCents)
    }

    enum CodingKeys: String, CodingKey {
        case invoiceLineId = "invoice_line_id"
        case description, quantity
        case unitPriceCents = "unit_price_cents"
    }
}

public struct PosReturnRequest: Encodable, Sendable {
    public let invoiceId: Int64
    public let reason: String?
    public let notes: String?
    public let tender: String
    public let lines: [PosReturnLineRequest]
    /// §16.9 — Restock flag. `true` = return item to inventory (stock +=qty);
    /// `false` = scrap (inventory unchanged). Sent to `POST /api/v1/pos/returns`.
    public let restock: Bool

    public init(
        invoiceId: Int64,
        reason: String?,
        notes: String?,
        tender: String,
        lines: [PosReturnLineRequest],
        restock: Bool = true
    ) {
        self.invoiceId = invoiceId
        self.reason = reason
        self.notes = notes
        self.tender = tender
        self.lines = lines
        self.restock = restock
    }

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
        case reason, notes, tender, lines, restock
    }
}

public struct PosReturnResponse: Decodable, Sendable {
    public let returnId: Int64?
    public let refundedCents: Int?
    public let tender: String?

    enum CodingKeys: String, CodingKey {
        case returnId = "return_id"
        case refundedCents = "refunded_cents"
        case tender
    }
}

/// Store-credit fallback body. Mirrors the `POST /refunds/credits/:customerId`
/// shape — a single-value credit with a free-text reason.
public struct CustomerCreditRefundRequest: Encodable, Sendable {
    public let amountCents: Int
    public let reason: String?
    public let sourceInvoiceId: Int64?

    public init(amountCents: Int, reason: String?, sourceInvoiceId: Int64?) {
        self.amountCents = max(0, amountCents)
        self.reason = reason
        self.sourceInvoiceId = sourceInvoiceId
    }

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
        case reason
        case sourceInvoiceId = "source_invoice_id"
    }
}

public struct CustomerCreditRefundResponse: Decodable, Sendable {
    public let creditId: Int64?
    public let balanceCents: Int?

    enum CodingKeys: String, CodingKey {
        case creditId = "credit_id"
        case balanceCents = "balance_cents"
    }
}

public extension APIClient {
    /// `POST /api/v1/pos/returns`. The POS UI wraps the thrown
    /// `APITransportError.httpStatus(404, ...)` with the store-credit
    /// fallback below before showing a "Coming soon" banner.
    func posReturn(_ request: PosReturnRequest) async throws -> PosReturnResponse {
        try await post("/api/v1/pos/returns", body: request, as: PosReturnResponse.self)
    }

    /// `POST /api/v1/refunds/credits/:customerId` — store-credit fallback
    /// for tenants whose server does not yet expose `/pos/returns`.
    func refundCustomerCredit(
        customerId: Int64,
        request: CustomerCreditRefundRequest
    ) async throws -> CustomerCreditRefundResponse {
        try await post(
            "/api/v1/refunds/credits/\(customerId)",
            body: request,
            as: CustomerCreditRefundResponse.self
        )
    }
}

// MARK: - Refund approval
// Server: PATCH /api/v1/refunds/:id/approve (admin only)

public struct RefundApprovalResponse: Decodable, Sendable {
    public let id: Int64
}

public extension APIClient {
    /// `PATCH /api/v1/refunds/:id/approve`
    /// Admin only. Atomically flips pending → completed and decrements invoice amount_paid.
    func approveRefund(refundId: Int64) async throws -> RefundApprovalResponse {
        try await patch("/api/v1/refunds/\(refundId)/approve",
                        body: RefundApproveBody(),
                        as: RefundApprovalResponse.self)
    }
}

private struct RefundApproveBody: Encodable, Sendable {}
