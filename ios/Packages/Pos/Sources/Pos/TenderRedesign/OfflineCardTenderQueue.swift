import Foundation
import Core
import Networking
import Sync
import Persistence

// MARK: - §16.23 Offline card tender queuing

/// Payload for `pos.card.tender.queued` sync ops.
///
/// When the device is offline at card tender submission time, the tender is
/// enqueued to the sync queue with this payload.  On drain, the executor calls
/// `POST /api/v1/invoices/:id/payments` with an idempotency key to prevent
/// double-charges.
///
/// ⚠ PAYMENT-MATH BOUNDARY: This type carries *only* the approved amount and
/// BlockChyp token/auth-code returned by the terminal before connectivity was
/// lost. The actual BlockChyp SDK call happens in Hardware/Terminal (Agent 2)
/// *before* this payload is created — we never store raw card data.
public struct OfflineCardTenderPayload: Codable, Sendable {
    /// Target invoice ID. `0` means the invoice itself is also queued.
    public let invoiceId: Int64
    /// Amount in cents that BlockChyp approved on the terminal.
    public let approvedAmountCents: Int
    /// BlockChyp token for the captured payment (opaque to us).
    public let blockChypToken: String?
    /// BlockChyp auth code from the terminal (opaque to us).
    public let authCode: String?
    /// Last-4 digits of the card (display only, never used for processing).
    public let last4: String?
    /// Card brand (display only).
    public let cardBrand: String?
    /// Idempotency key. Must be forwarded to `POST /api/v1/invoices/:id/payments`.
    public let idempotencyKey: String
    /// Signature base64 PNG (if captured before going offline). May be nil.
    public let signatureBase64: String?
    /// Timestamp the tender was captured on the terminal (for receipt).
    public let capturedAt: Date

    public init(
        invoiceId: Int64,
        approvedAmountCents: Int,
        blockChypToken: String? = nil,
        authCode: String? = nil,
        last4: String? = nil,
        cardBrand: String? = nil,
        idempotencyKey: String = UUID().uuidString,
        signatureBase64: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.invoiceId = invoiceId
        self.approvedAmountCents = approvedAmountCents
        self.blockChypToken = blockChypToken
        self.authCode = authCode
        self.last4 = last4
        self.cardBrand = cardBrand
        self.idempotencyKey = idempotencyKey
        self.signatureBase64 = signatureBase64
        self.capturedAt = capturedAt
    }
}

// MARK: - Request body for invoice payment record

/// Body sent to `POST /api/v1/invoices/:id/payments` when draining the queue.
/// Mirrors the server's `RecordPaymentBody` shape in `invoices.routes.ts`.
private struct RecordInvoicePaymentBody: Encodable, Sendable {
    let amountCents: Int
    let tenderMethod: String       // always "card" for this path
    let blockChypToken: String?
    let authCode: String?
    let last4: String?
    let cardBrand: String?
    let sigBase64: String?
    let idempotencyKey: String
    let capturedAt: String         // ISO-8601

    enum CodingKeys: String, CodingKey {
        case amountCents     = "amount_cents"
        case tenderMethod    = "tender_method"
        case blockChypToken  = "blockchyp_token"
        case authCode        = "auth_code"
        case last4
        case cardBrand       = "card_brand"
        case sigBase64       = "sig_base64"
        case idempotencyKey  = "idempotency_key"
        case capturedAt      = "captured_at"
    }
}

// MARK: - OfflineCardTenderService

/// §16.23 — Queues approved-but-unrecorded card tenders to the sync queue so
/// they survive app restart and connectivity loss.
///
/// Usage (in PosTenderViewModel after BlockChyp approval returns):
/// ```swift
/// if networkMonitor.isOffline {
///     await OfflineCardTenderService.shared.enqueue(payload)
///     vm.applyTender(AppliedTenderEntry(label: "Card (queued)", amountCents: payload.approvedAmountCents))
/// } else {
///     // record immediately via APIClient+POS
/// }
/// ```
///
/// Sovereignty: all data flows through `APIClient.baseURL` (tenant server only).
/// No BlockChyp token is ever sent to any third-party endpoint from this code.
public actor OfflineCardTenderService {

    public static let shared = OfflineCardTenderService()
    private let queueStore: SyncQueueStore

    public init(queueStore: SyncQueueStore = .shared) {
        self.queueStore = queueStore
    }

    // MARK: - Enqueue

    /// Enqueue an offline-approved card tender to the sync queue.
    /// The drain loop will call `POST /api/v1/invoices/:id/payments` when
    /// connectivity is restored.
    ///
    /// - Parameter payload: Approved tender metadata (no raw card data).
    public func enqueue(_ payload: OfflineCardTenderPayload) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let record = SyncQueueRecord(
            op: "payment",
            entity: "invoice",
            entityServerId: "\(payload.invoiceId)",
            payload: payloadString,
            idempotencyKey: payload.idempotencyKey,
            enqueuedAt: payload.capturedAt
        )
        try await queueStore.enqueue(record)
        AppLog.pos.info(
            "Offline card tender queued invoiceId=\(payload.invoiceId) amount=\(payload.approvedAmountCents)c key=\(payload.idempotencyKey, privacy: .public)"
        )
    }

    // MARK: - Pending count (for UI badge)

    /// Number of pending ops in the sync queue (includes all POS ops, not only card).
    public func pendingCount() async throws -> Int {
        try await queueStore.pendingCount()
    }
}

// MARK: - PosSyncOpExecutor extension for pos.card.tender.queued

/// §16.23 — Extend `PosSyncOpExecutor.execute` to handle
/// `pos.card.tender.queued` ops. Added as a separate file to avoid
/// modifying the executor's primary file.
///
/// Registered in `PosSyncOpExecutor.execute(_:)` via the switch statement.
/// The executor calls `recordInvoicePayment` on drain.
public final class PosCardTenderSyncHandler: Sendable {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Execute a `pos.card.tender.queued` sync record.
    /// Calls `POST /api/v1/invoices/:id/payments`.
    /// A 409 (idempotency duplicate) is treated as success — the payment was
    /// already recorded by a prior drain attempt.
    public func execute(_ record: SyncQueueRecord) async throws {
        let payloadData = Data(record.payload.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(OfflineCardTenderPayload.self, from: payloadData)

        let iso = ISO8601DateFormatter()
        let body = RecordInvoicePaymentBody(
            amountCents: payload.approvedAmountCents,
            tenderMethod: "card",
            blockChypToken: payload.blockChypToken,
            authCode: payload.authCode,
            last4: payload.last4,
            cardBrand: payload.cardBrand,
            sigBase64: payload.signatureBase64,
            idempotencyKey: payload.idempotencyKey,
            capturedAt: iso.string(from: payload.capturedAt)
        )

        do {
            _ = try await api.post(
                "/api/v1/invoices/\(payload.invoiceId)/payments",
                body: body,
                as: EmptyAPIResponse.self
            )
            AppLog.pos.info(
                "Offline card tender drained invoiceId=\(payload.invoiceId) key=\(payload.idempotencyKey, privacy: .public)"
            )
        } catch APITransportError.httpStatus(409, _) {
            // Idempotency hit — already recorded. Treat as success.
            AppLog.pos.info(
                "Offline card tender 409 (already recorded) invoiceId=\(payload.invoiceId)"
            )
        }
    }
}

/// Minimal decodable for API responses that return only `{ success }`.
private struct EmptyAPIResponse: Decodable, Sendable {
    let success: Bool?
}
