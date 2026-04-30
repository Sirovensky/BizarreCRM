import Foundation

/// §39 — DTOs for the cash-register endpoints documented in
/// `docs/ios-api-gap-audit.md`.
///
/// At the time of writing `POST /pos/cash-sessions` + its close/z-report
/// siblings are not implemented server-side (ticket `POS-SESSIONS-001`).
/// These wrappers throw `APITransportError.httpStatus(501, ...)` so the UI
/// can fall back to the local-only flow in `CashRegisterStore` until the
/// server catches up.
///
/// When the endpoints land, the only change needed here is to remove the
/// `throw` stub in each wrapper and uncomment the actual POST/GET call.

// MARK: - Open session

/// Wire format for `POST /pos/cash-sessions`.
public struct OpenCashSessionRequest: Encodable, Sendable {
    public let openingFloatCents: Int
    public let notes: String?

    public init(openingFloatCents: Int, notes: String? = nil) {
        self.openingFloatCents = openingFloatCents
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case openingFloatCents = "opening_float_cents"
        case notes
    }
}

public struct CashSessionDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let openedAt: String?
    public let openingFloatCents: Int?
    public let closedAt: String?
    public let countedCents: Int?
    public let expectedCents: Int?
    public let varianceCents: Int?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case openedAt           = "opened_at"
        case openingFloatCents  = "opening_float_cents"
        case closedAt           = "closed_at"
        case countedCents       = "closing_counted_cents"
        case expectedCents      = "expected_cents"
        case varianceCents      = "variance_cents"
        case notes
    }
}

// MARK: - Close session

public struct CloseCashSessionRequest: Encodable, Sendable {
    public let closingCountedCents: Int
    public let notes: String?

    public init(closingCountedCents: Int, notes: String? = nil) {
        self.closingCountedCents = closingCountedCents
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case closingCountedCents = "closing_counted_cents"
        case notes
    }
}

// MARK: - Z-Report

public struct ZReportPaymentBreakdown: Decodable, Sendable {
    public let method: String
    public let cents: Int
    public let count: Int
}

public struct ZReportTotals: Decodable, Sendable {
    public let grossCents: Int
    public let refundCents: Int
    public let netCents: Int
    public let transactionCount: Int

    enum CodingKeys: String, CodingKey {
        case grossCents        = "gross_cents"
        case refundCents       = "refund_cents"
        case netCents          = "net_cents"
        case transactionCount  = "transaction_count"
    }
}

public struct ZReportDTO: Decodable, Sendable {
    public let shiftId: Int64
    public let openedAt: String?
    public let closedAt: String?
    public let openingFloatCents: Int
    public let expectedCents: Int
    public let countedCents: Int
    public let varianceCents: Int
    public let paymentBreakdown: [ZReportPaymentBreakdown]
    public let totals: ZReportTotals

    enum CodingKeys: String, CodingKey {
        case shiftId            = "shift_id"
        case openedAt           = "opened_at"
        case closedAt           = "closed_at"
        case openingFloatCents  = "opening_float_cents"
        case expectedCents      = "expected_cents"
        case countedCents       = "counted_cents"
        case varianceCents      = "variance_cents"
        case paymentBreakdown   = "payment_breakdown"
        case totals
    }
}

public extension APIClient {
    /// `POST /pos/cash-sessions`. Currently stubbed — see file header.
    func openCashSession(openingFloatCents: Int, notes: String? = nil) async throws -> CashSessionDTO {
        // Server ticket POS-SESSIONS-001 is still open. Surface a typed
        // 501 so the local-first path at the call site stays the
        // authoritative write; swap to the real POST when the endpoint
        // ships (no DTO changes expected).
        throw APITransportError.httpStatus(501, message: "Coming soon — POS-SESSIONS-001")
        // let req = OpenCashSessionRequest(openingFloatCents: openingFloatCents, notes: notes)
        // return try await post("/api/v1/pos/cash-sessions", body: req, as: CashSessionDTO.self)
    }

    /// `POST /pos/cash-sessions/:id/close`.
    func closeCashSession(id: Int64, countedCents: Int, notes: String? = nil) async throws -> ZReportDTO {
        throw APITransportError.httpStatus(501, message: "Coming soon — POS-SESSIONS-001")
        // let req = CloseCashSessionRequest(closingCountedCents: countedCents, notes: notes)
        // return try await post("/api/v1/pos/cash-sessions/\(id)/close", body: req, as: ZReportDTO.self)
    }

    /// `GET /pos/cash-sessions/:id/z-report`.
    func getZReport(sessionId: Int64) async throws -> ZReportDTO {
        throw APITransportError.httpStatus(501, message: "Coming soon — POS-SESSIONS-001")
        // return try await get("/api/v1/pos/cash-sessions/\(sessionId)/z-report", as: ZReportDTO.self)
    }

    /// §39.3 — `GET /cash-register/x-report` — peek current shift without closing.
    ///
    /// X-report = mid-shift totals view. Server route: `/cash-register/x-report`.
    /// Status: endpoint exists (per `docs/ios-api-gap-audit.md`).
    ///
    /// The response shape mirrors `ZReportDTO` but the session stays open.
    func getXReport() async throws -> ZReportDTO {
        // Route confirmed at packages/server/src/routes/pos.routes.ts — uses the
        // same DTO shape as Z-report but session status stays "open".
        // Stub until server-side ticket POS-XREPORT-001 is merged.
        throw APITransportError.httpStatus(501, message: "Coming soon — POS-XREPORT-001")
        // return try await get("/api/v1/cash-register/x-report", as: ZReportDTO.self)
    }
}
