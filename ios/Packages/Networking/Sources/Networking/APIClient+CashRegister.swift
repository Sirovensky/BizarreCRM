import Foundation

/// Cash-register / POS register endpoint wrappers.
///
/// Server routes (packages/server/src/routes/pos.routes.ts):
///   GET  /api/v1/pos/register      — today's register state
///   POST /api/v1/pos/cash-in       — cash-in event
///   POST /api/v1/pos/cash-out      — cash-out event
///   POST /api/v1/pos/cash/sessions/open  — open a cash session (sync)
///   POST /api/v1/pos/returns       — record a return
///   POST /api/v1/pos/sale/finalize — finalize a POS sale
///
/// All envelope: `{ success: Bool, data: T?, message: String? }`.

// MARK: - Shared empty response sentinel

/// Used when only success/failure matters (POST endpoints that return no body).
public struct PosEmptyResponse: Decodable, Sendable {}

// MARK: - Register state DTOs (mirrors CashSessionRepository.swift in Pos)
// NOTE: These types are re-declared here so the Networking layer is self-contained.
// The Pos package imports Networking and uses its own protocol-typed wrappers.

// MARK: - APIClient extension

public extension APIClient {

    // MARK: Register state

    /// `GET /api/v1/pos/register` — fetch today's register totals + entries.
    func getPosRegisterState() async throws -> PosRegisterStateResponse {
        try await get("/api/v1/pos/register", as: PosRegisterStateResponse.self)
    }

    // MARK: Cash movements

    /// `POST /api/v1/pos/cash-in` — record a cash-in event.
    func postPosCashIn(amountCents: Int, reason: String?) async throws -> PosCashMoveResponse {
        let body = PosCashMoveBody(amount: amountCents, reason: reason)
        return try await post("/api/v1/pos/cash-in", body: body, as: PosCashMoveResponse.self)
    }

    /// `POST /api/v1/pos/cash-out` — record a cash-out event.
    func postPosCashOut(amountCents: Int, reason: String?) async throws -> PosCashMoveResponse {
        let body = PosCashMoveBody(amount: amountCents, reason: reason)
        return try await post("/api/v1/pos/cash-out", body: body, as: PosCashMoveResponse.self)
    }

    // MARK: Sync ops (used by PosSyncOpExecutor)

    /// `POST /api/v1/pos/sale/finalize` — finalize an offline-queued sale.
    /// Throws `APITransportError.httpStatus(409, _)` on duplicate / conflict.
    func posFinalizeSale<B: Encodable & Sendable>(_ body: B) async throws {
        _ = try await post("/api/v1/pos/sale/finalize", body: body, as: PosEmptyResponse.self)
    }

    /// `POST /api/v1/pos/returns` — submit a return record.
    func posCreateReturn<B: Encodable & Sendable>(_ body: B) async throws {
        _ = try await post("/api/v1/pos/returns", body: body, as: PosEmptyResponse.self)
    }

    /// `POST /api/v1/pos/cash/sessions/open` — server-side cash session open.
    func posCashSessionOpen<B: Encodable & Sendable>(_ body: B) async throws {
        _ = try await post("/api/v1/pos/cash/sessions/open", body: body, as: PosEmptyResponse.self)
    }

    // MARK: Sale search / reprint (used by Reprint flow)

    /// `GET /api/v1/sales/:id` — fetch a single sale record.
    func getSale<T: Decodable & Sendable>(id: Int64, as type: T.Type) async throws -> T {
        try await get("/api/v1/sales/\(id)", as: type)
    }

    /// `GET /api/v1/sales/search?q=<query>` — search past sales.
    func searchSales<T: Decodable & Sendable>(query: String, as type: T.Type) async throws -> T {
        let items = [URLQueryItem(name: "q", value: query)]
        return try await get("/api/v1/sales/search", query: items, as: type)
    }

    /// `POST /api/v1/sales/:id/reprint-event` — audit log for reprints.
    func postReprintEvent<B: Encodable & Sendable>(saleId: Int64, body: B) async throws {
        _ = try await post("/api/v1/sales/\(saleId)/reprint-event", body: body, as: PosEmptyResponse.self)
    }

    // MARK: Coupons (used by CouponRepository)

    /// `GET /api/v1/coupons` — list all coupon codes.
    func listCoupons<T: Decodable & Sendable>(as type: T.Type) async throws -> T {
        try await get("/api/v1/coupons", as: type)
    }

    /// `POST /api/v1/coupons/batch` — batch-generate coupon codes.
    func batchGenerateCoupons<B: Encodable & Sendable, T: Decodable & Sendable>(body: B, as type: T.Type) async throws -> T {
        try await post("/api/v1/coupons/batch", body: body, as: type)
    }

    /// `PATCH /api/v1/coupons/:id` — update a coupon (e.g. mark expired).
    func patchCoupon<B: Encodable & Sendable, T: Decodable & Sendable>(id: String, body: B, as type: T.Type) async throws -> T {
        try await patch("/api/v1/coupons/\(id)", body: body, as: type)
    }

    /// `DELETE /api/v1/coupons/:id` — delete a coupon code.
    func deleteCoupon(id: String) async throws {
        try await delete("/api/v1/coupons/\(id)")
    }

    // MARK: Reconciliation (§39.4)

    /// `GET /api/v1/pos/reconciliation/daily?date=YYYY-MM-DD`
    /// Server ticket: POS-RECON-001. Returns daily tie-out metrics.
    /// Gracefully degrades to `.unavailable` on 404/501.
    func getDailyReconciliation<T: Decodable & Sendable>(date: String, as type: T.Type) async throws -> T {
        let query = [URLQueryItem(name: "date", value: date)]
        return try await get("/api/v1/pos/reconciliation/daily", query: query, as: type)
    }

    /// `GET /api/v1/pos/reconciliation/monthly?month=YYYY-MM`
    /// Full monthly report (revenue, COGS, AR aging, AP aging). POS-RECON-001.
    func getMonthlyReconciliation<T: Decodable & Sendable>(month: String, as type: T.Type) async throws -> T {
        let query = [URLQueryItem(name: "month", value: month)]
        return try await get("/api/v1/pos/reconciliation/monthly", query: query, as: type)
    }

    /// `GET /api/v1/pos/reconciliation/drill?date=YYYY-MM-DD`
    /// Variance drill entries for a specific day. POS-RECON-002.
    func getVarianceDrill<T: Decodable & Sendable>(date: String, as type: T.Type) async throws -> T {
        let query = [URLQueryItem(name: "date", value: date)]
        return try await get("/api/v1/pos/reconciliation/drill", query: query, as: type)
    }

    // MARK: Notifications (used by PosReceiptViewModel)

    /// Send a receipt via email or SMS.
    ///
    /// BUGHUNT-2026-05-17: previously POSTed `{invoiceId, channel,
    /// destination}` to `/notifications/send-receipt`. Server actually
    /// has TWO separate routes — `/send-receipt` (email) reads
    /// `{invoice_id, recipient_email}` and `/send-receipt-sms` reads
    /// `{invoice_id, recipient_phone}` (see notifications.routes.ts
    /// L207 and L376). There is no `channel` discriminator. The
    /// previous body never matched the destructure, so every receipt
    /// dispatch from PosReceiptViewModel hit `recipient_email required`
    /// or `invoice_id required` and 400'd.
    ///
    /// - Parameters:
    ///   - invoiceId:   Server invoice ID.
    ///   - channel:     `"email"` or `"sms"` — selects which server route to hit.
    ///   - destination: Email address (email channel) or phone number (sms channel).
    /// - Returns: Server `messageId` when available.
    func postSendReceipt(invoiceId: Int64, channel: String, destination: String) async throws -> String? {
        switch channel.lowercased() {
        case "sms":
            let body = PosNotificationSendReceiptSmsBody(invoiceId: invoiceId, recipientPhone: destination)
            let resp = try await post("/api/v1/notifications/send-receipt-sms", body: body, as: PosNotificationSendReceiptResponse.self)
            return resp.data?.messageId
        default:
            // Default to email for any other channel value — the UI only
            // ever passes "email" or "sms" but this matches the previous
            // behaviour of falling through to the email endpoint.
            let body = PosNotificationSendReceiptEmailBody(invoiceId: invoiceId, recipientEmail: destination)
            let resp = try await post("/api/v1/notifications/send-receipt", body: body, as: PosNotificationSendReceiptResponse.self)
            return resp.data?.messageId
        }
    }
}

// MARK: - DTOs

/// Response from `GET /api/v1/pos/register`.
public struct PosRegisterStateResponse: Decodable, Sendable {
    public let cashIn: Int
    public let cashOut: Int
    public let cashSales: Int
    public let net: Int
    public let entries: [PosCashEntryDTO]

    enum CodingKeys: String, CodingKey {
        case cashIn    = "cash_in"
        case cashOut   = "cash_out"
        case cashSales = "cash_sales"
        case net
        case entries
    }
}

/// A single register entry from `GET /api/v1/pos/register`.
public struct PosCashEntryDTO: Decodable, Sendable, Identifiable {
    public let id: Int
    public let type: String
    public let amount: Int
    public let reason: String?
    public let userName: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, amount, reason
        case userName  = "user_name"
        case createdAt = "created_at"
    }
}

/// Response from `POST /api/v1/pos/cash-in` or `POST /api/v1/pos/cash-out`.
public struct PosCashMoveResponse: Decodable, Sendable {
    public let entry: PosCashEntryDTO
}

// MARK: - Private request bodies

private struct PosCashMoveBody: Encodable, Sendable {
    let amount: Int
    let reason: String?
}

// BUGHUNT-2026-05-17: replaced the old `PosNotificationSendReceiptBody`
// with channel-specific bodies that match each server route's destructure.
// The previous "destination" field name had no server counterpart and the
// `channel` field doesn't exist on either route.

private struct PosNotificationSendReceiptEmailBody: Encodable, Sendable {
    let invoiceId: Int64
    let recipientEmail: String

    enum CodingKeys: String, CodingKey {
        case invoiceId      = "invoice_id"
        case recipientEmail = "recipient_email"
    }
}

private struct PosNotificationSendReceiptSmsBody: Encodable, Sendable {
    let invoiceId: Int64
    let recipientPhone: String

    enum CodingKeys: String, CodingKey {
        case invoiceId      = "invoice_id"
        case recipientPhone = "recipient_phone"
    }
}

// MARK: - Notification response DTOs

/// Response from `POST /api/v1/notifications/send-receipt`.
public struct PosNotificationSendReceiptResponse: Decodable, Sendable {
    public let success: Bool
    public struct DataPayload: Decodable, Sendable {
        public let messageId: String?
    }
    public let data: DataPayload?
}
