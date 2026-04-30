import Foundation
import Networking

// §7.4 InvoiceReceiptDeliveryRepository — wraps the email-receipt and SMS-send calls
// so all APIClient invocations live in a *Repository file per §20 containment.

public protocol InvoiceReceiptDeliveryRepository: Sendable {
    /// POST /api/v1/invoices/:id/email-receipt
    func emailReceipt(invoiceId: Int64, email: String) async throws
    /// POST /api/v1/sms/send
    func smsReceipt(phone: String, message: String) async throws
}

public actor InvoiceReceiptDeliveryRepositoryImpl: InvoiceReceiptDeliveryRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func emailReceipt(invoiceId: Int64, email: String) async throws {
        struct Body: Encodable, Sendable { let email: String }
        struct Response: Decodable, Sendable { let success: Bool? }
        _ = try await api.post(
            "/api/v1/invoices/\(invoiceId)/email-receipt",
            body: Body(email: email),
            as: Response.self
        )
    }

    public func smsReceipt(phone: String, message: String) async throws {
        struct Body: Encodable, Sendable { let to: String; let message: String }
        struct Response: Decodable, Sendable { let success: Bool? }
        _ = try await api.post(
            "/api/v1/sms/send",
            body: Body(to: phone, message: message),
            as: Response.self
        )
    }
}
