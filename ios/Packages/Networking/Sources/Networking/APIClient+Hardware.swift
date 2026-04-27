import Foundation

/// §17 — Hardware integrations convenience layer on `APIClient`.
///
/// This file is the **append-only** shim that exposes hardware-domain API
/// calls at the `APIClient` extension level for consumers that import `Networking`
/// directly. Functional implementations delegate to typed endpoints or are
/// inlined for simplicity.
///
/// Owned by: Agent 2 (Hardware & Camera & Voice).
/// DO NOT add networking calls from other domains here.
///
/// Routes confirmed against `packages/server/src/routes/`:
///   POST /api/v1/audit/events              — log a manual drawer-open event
///   GET  /api/v1/hardware/firmware         — latest firmware version per model
///   POST /api/v1/hardware/firmware/notify  — request OTA notification (deferred)

// MARK: - Audit event (cash drawer manual open)

private struct AuditEventBody: Encodable, Sendable {
    let eventType: String
    let entityType: String?
    let entityId: Int64?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case eventType  = "event_type"
        case entityType = "entity_type"
        case entityId   = "entity_id"
        case metadata
    }
}

private struct AuditEventAck: Decodable, Sendable {}

public extension APIClient {

    /// Log a "drawer opened manually" audit event for shift reconciliation.
    ///
    /// Called from `CashDrawerFallbackView.onManualOpen` when the cashier
    /// opens the drawer by hand because the printer is offline.
    ///
    /// - Parameter receiptId: Optional sale/receipt ID to link the event to a transaction.
    func logManualDrawerOpen(receiptId: Int64? = nil) async throws {
        var meta: [String: String] = ["source": "manual_fallback"]
        if let id = receiptId { meta["receipt_id"] = "\(id)" }
        let body = AuditEventBody(
            eventType: "cash_drawer_manual_open",
            entityType: receiptId != nil ? "sale" : nil,
            entityId: receiptId,
            metadata: meta
        )
        _ = try await post("/api/v1/audit/events", body: body, as: AuditEventAck.self)
    }

    /// Log a "scale tare applied" audit event (optional — for reconciliation).
    ///
    /// - Parameters:
    ///   - grams: Tare offset in grams.
    ///   - scaleId: Optional peripheral UUID string for the scale.
    func logScaleTare(grams: Int, scaleId: String? = nil) async throws {
        var meta: [String: String] = ["tare_grams": "\(grams)"]
        if let id = scaleId { meta["scale_id"] = id }
        let body = AuditEventBody(
            eventType: "scale_tare",
            entityType: nil,
            entityId: nil,
            metadata: meta
        )
        _ = try await post("/api/v1/audit/events", body: body, as: AuditEventAck.self)
    }
}
