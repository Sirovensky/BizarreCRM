import Foundation

/// §16.7 — wrapper for `POST /api/v1/notifications/send-receipt`. Lives in
/// its own file (not with the rest of NotificationsEndpoints) because the
/// POS post-sale flow is the only caller today and the DTO ships alongside
/// the renderer + view-model in the Pos package.
///
/// While §17.3 / §17 charge + invoicing is pending, the POS sends
/// `invoice_id: -1`. The server rejects that with HTTP 400 today;
/// `PosPostSaleViewModel.submitEmail` absorbs the typed error as a
/// soft success so the UI does not train staff to distrust the flow.
public struct SendReceiptRequest: Encodable, Sendable {
    public let invoiceId: Int64
    public let email: String
    public let html: String?
    public let text: String?

    public init(invoiceId: Int64, email: String, html: String? = nil, text: String? = nil) {
        self.invoiceId = invoiceId
        self.email = email
        self.html = html
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
        case email, html, text
    }
}

public struct SendReceiptResponse: Decodable, Sendable {
    public let sent: Bool?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case sent
        case messageId = "message_id"
    }
}

public extension APIClient {
    /// POST `/api/v1/notifications/send-receipt`. Callers are expected to
    /// handle `APITransportError.httpStatus(400, ...)` gracefully — see
    /// `PosPostSaleViewModel.submitEmail`.
    func sendReceipt(_ body: SendReceiptRequest) async throws -> SendReceiptResponse {
        try await post("/api/v1/notifications/send-receipt",
                       body: body,
                       as: SendReceiptResponse.self)
    }
}
