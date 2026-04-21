import Foundation
import Networking

// MARK: - §41.4 Partial payment support

/// Toggles partial payments on a payment link and carries the current
/// paid amount + remaining balance. All money in cents.
public struct PartialPaymentSupport: Sendable, Equatable {
    public let paymentLinkId: Int64
    public let allowPartial: Bool

    public init(paymentLinkId: Int64, allowPartial: Bool) {
        self.paymentLinkId = paymentLinkId
        self.allowPartial = allowPartial
    }
}

// MARK: - Payment history entry

/// One installment recorded on a payment link.
public struct PartialPayment: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let amountCents: Int
    public let paidAt: String
    public let method: String?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case amountCents = "amount_cents"
        case paidAt      = "paid_at"
        case method, note
    }

    public init(
        id: Int64,
        amountCents: Int,
        paidAt: String,
        method: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.amountCents = amountCents
        self.paidAt = paidAt
        self.method = method
        self.note = note
    }
}

// MARK: - Enable partial request

/// Sent to `PATCH /payment-links/:id` to enable or disable partial payments.
public struct UpdatePartialPaymentRequest: Encodable, Sendable {
    public let allowPartial: Bool

    public init(allowPartial: Bool) {
        self.allowPartial = allowPartial
    }

    enum CodingKeys: String, CodingKey {
        case allowPartial = "allow_partial"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `PATCH /payment-links/:id` — toggle partial-payment flag.
    func setPartialPayment(linkId: Int64, allow: Bool) async throws -> PaymentLink {
        let body = UpdatePartialPaymentRequest(allowPartial: allow)
        return try await patch(
            "/api/v1/payment-links/\(linkId)",
            body: body,
            as: PaymentLink.self
        )
    }

    /// `GET /payment-links/:id/payments` — full payment history.
    func listPartialPayments(linkId: Int64) async throws -> [PartialPayment] {
        try await get("/api/v1/payment-links/\(linkId)/payments", as: [PartialPayment].self)
    }
}
