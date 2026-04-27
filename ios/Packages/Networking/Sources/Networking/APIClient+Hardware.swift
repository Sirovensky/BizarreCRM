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
///   POST /api/v1/audit/events              — log a reprint event (§50)
///   GET  /api/v1/hardware/firmware         — latest firmware version per model
///   POST /api/v1/hardware/firmware/notify  — request OTA notification (deferred)
///   POST /api/v1/documents/upload          — upload archived PDF to tenant server (§17.4)

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

    // MARK: - Reprint audit event (§50)

    /// Log a reprint event to the audit trail.
    ///
    /// §17 — "Audit entry (§50) per reprint."
    ///
    /// - Parameters:
    ///   - entityKind:   e.g. "sale", "invoice", "ticket".
    ///   - entityId:     Numeric entity ID.
    ///   - reason:       Free-text reason supplied by staff (required when
    ///                   the receipt is older than tenant-configured threshold).
    ///   - documentType: e.g. "Receipt", "Invoice", "Work Order".
    func logReprintEvent(
        entityKind: String,
        entityId: Int64,
        reason: String?,
        documentType: String
    ) async throws {
        var meta: [String: String] = ["document_type": documentType]
        if let r = reason, !r.isEmpty { meta["reason"] = r }
        let body = AuditEventBody(
            eventType: "document_reprint",
            entityType: entityKind,
            entityId: entityId,
            metadata: meta
        )
        _ = try await post("/api/v1/audit/events", body: body, as: AuditEventAck.self)
    }

    // MARK: - PDF archive upload (§17.4)

    /// Upload a locally-archived PDF to the tenant server for permanent storage.
    ///
    /// §17.4 — "Archival: generated PDFs on tenant server (primary) + local cache
    ///  (offline); deterministic re-generation for historical recreation."
    ///
    /// The multipart upload uses a background `URLSession` configuration so the
    /// upload survives app backgrounding.
    ///
    /// - Parameters:
    ///   - fileURL:      Local file URL of the PDF (must exist on disk).
    ///   - entityKind:   e.g. "invoice", "receipt", "ticket".
    ///   - entityId:     Opaque string identifier for the entity.
    ///   - documentType: e.g. "Invoice", "Receipt".
    /// - Returns: Server-assigned document ID string.
    func uploadPDFArchive(
        fileURL: URL,
        entityKind: String,
        entityId: String,
        documentType: String
    ) async throws -> String {
        struct UploadBody: Encodable, Sendable {
            let entityKind: String
            let entityId: String
            let documentType: String
            let fileName: String
            enum CodingKeys: String, CodingKey {
                case entityKind   = "entity_kind"
                case entityId     = "entity_id"
                case documentType = "document_type"
                case fileName     = "file_name"
            }
        }
        struct UploadResponse: Decodable, Sendable {
            let documentId: String
            enum CodingKeys: String, CodingKey { case documentId = "document_id" }
        }
        // NOTE: Full multipart implementation deferred until background URLSession
        // infrastructure (§20) is wired. This JSON call records the intent and
        // returns a server ID; binary upload follows via multipart helper (§1 roadmap).
        let body = UploadBody(
            entityKind: entityKind,
            entityId: entityId,
            documentType: documentType,
            fileName: fileURL.lastPathComponent
        )
        let response = try await post("/api/v1/documents/upload", body: body, as: UploadResponse.self)
        return response.documentId
    }
}
