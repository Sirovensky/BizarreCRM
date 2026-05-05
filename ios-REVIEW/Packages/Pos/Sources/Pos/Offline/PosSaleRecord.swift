#if canImport(UIKit)
import Foundation
import Core

// MARK: - PosSaleRecord (§16.12 offline sale schema)

/// Canonical local sale record written to GRDB `pos_sale_records` table
/// before the POS sends the payload to the server.
///
/// **Purpose:**
/// - Idempotency: `idempotencyKey` prevents duplicate ledger entries if the
///   network request is retried (server checks for duplicate keys).
/// - Offline watermark: `syncedAt == nil` drives the "OFFLINE" receipt
///   watermark; the watermark clears once `syncedAt` is set.
/// - Audit: `offlineStartedAt` + `syncedAt` give the manager report:
///   "3 sales during a 20-min outage — all reconciled."
///
/// **PCI posture:**
/// Card data is NEVER stored in this record. `AppliedTender` stores only
/// `last4`, `brand`, and a `blockchypToken` (opaque reference). Raw PANs
/// are processed exclusively inside the BlockChyp terminal / SDK process
/// and never passed to this layer.
public struct PosSaleRecord: Identifiable, Codable, Sendable {

    // MARK: - Identity

    /// Client-generated UUID. Used as the primary key in GRDB and as the
    /// server idempotency key via the `Idempotency-Key: <uuid>` HTTP header.
    public let idempotencyKey: String

    /// Client-local integer ID (GRDB autoincrement). Set after first insert.
    public var id: Int64?

    // MARK: - Sale content

    /// UTC timestamp of sale capture (before sync).
    public let capturedAt: Date

    /// Serialised cart snapshot (all lines, quantities, prices).
    public let lines: [PosSaleLineRecord]

    /// Applied tenders (cash / gift card / store credit / check etc.).
    /// Card tenders store only `last4` + `brand` + opaque token — never PAN.
    public let tenders: [PosSaleTenderRecord]

    /// Total in cents as computed by `CartMath` on the client.
    public let totalCents: Int

    /// Optional idempotency key for the associated shift / cash session.
    public let cashSessionId: Int64?

    /// Optional linked ticket or invoice ID.
    public let linkedTicketId: Int64?

    // MARK: - Sync lifecycle

    /// Set to `true` when the sale was captured while the device was offline.
    /// Displayed as the "OFFLINE" watermark on the receipt until `syncedAt`
    /// is non-nil.
    public var capturedOffline: Bool

    /// Wall-clock date at which the device was confirmed offline when this
    /// sale was captured. Used for the manager outage report.
    public var offlineStartedAt: Date?

    /// UTC timestamp set by the sync drain loop when the server confirms the
    /// sale and returns a canonical invoice ID. `nil` = not yet synced.
    public var syncedAt: Date?

    /// Server-assigned invoice ID after successful sync. Replaces the
    /// local `idempotencyKey` as the canonical reference.
    public var serverInvoiceId: Int64?

    // MARK: - Init

    public init(
        idempotencyKey: String = UUID().uuidString,
        capturedAt: Date = .now,
        lines: [PosSaleLineRecord],
        tenders: [PosSaleTenderRecord],
        totalCents: Int,
        cashSessionId: Int64? = nil,
        linkedTicketId: Int64? = nil,
        capturedOffline: Bool = false,
        offlineStartedAt: Date? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.capturedAt = capturedAt
        self.lines = lines
        self.tenders = tenders
        self.totalCents = totalCents
        self.cashSessionId = cashSessionId
        self.linkedTicketId = linkedTicketId
        self.capturedOffline = capturedOffline
        self.offlineStartedAt = offlineStartedAt
    }
}

// MARK: - PosSaleLineRecord

/// Snapshot of a single cart line at time of sale.
public struct PosSaleLineRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let sku: String?
    public let inventoryItemId: Int64?
    public let quantity: Int
    public let unitPriceCents: Int
    public let discountCents: Int
    public let taxCents: Int
    public let lineTotalCents: Int

    public init(
        id: UUID = UUID(),
        name: String,
        sku: String? = nil,
        inventoryItemId: Int64? = nil,
        quantity: Int,
        unitPriceCents: Int,
        discountCents: Int = 0,
        taxCents: Int = 0,
        lineTotalCents: Int
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.inventoryItemId = inventoryItemId
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.discountCents = discountCents
        self.taxCents = taxCents
        self.lineTotalCents = lineTotalCents
    }
}

// MARK: - PosSaleTenderRecord

/// Snapshot of one tender leg. Card tenders must NEVER include raw PAN.
/// Only last4, brand, and a BlockChyp opaque token (if applicable).
public struct PosSaleTenderRecord: Codable, Sendable {
    public let method: String        // "cash" | "gift_card" | "store_credit" | "check" etc.
    public let amountCents: Int
    public let reference: String?    // last4 for card, code for gift card — no full PAN
    public let blockchypToken: String? // Opaque server-side token; nil for non-card tenders
    public let iouApproved: Bool     // true if accepted as offline IOU (manager-gated)

    public init(
        method: String,
        amountCents: Int,
        reference: String? = nil,
        blockchypToken: String? = nil,
        iouApproved: Bool = false
    ) {
        self.method = method
        self.amountCents = amountCents
        self.reference = reference
        self.blockchypToken = blockchypToken
        self.iouApproved = iouApproved
    }
}

// MARK: - Offline-specific policy helpers

extension PosSaleRecord {

    /// Determines whether a given tender method is allowed without a network
    /// connection.
    ///
    /// **POS offline policy (§16.12):**
    /// - Cash: always OK (no auth needed).
    /// - Check: always OK (goes to A/R on sync; no auth needed).
    /// - Gift card: **requires online** for balance lookup. Cashier must show
    ///   the "Card balance lookup needs internet" error and offer IOU mode
    ///   (manager PIN gated) if the customer insists.
    /// - Store credit: requires online for balance lookup (same rationale as gift card).
    /// - Card (BlockChyp): offline capture where supported — handled by
    ///   BlockChyp SDK; not represented here.
    /// - Account credit / net-30: requires online to verify customer terms.
    ///
    /// Returns `true` if the tender is unconditionally usable offline.
    public static func isOfflineSafe(tenderMethod: String) -> Bool {
        switch tenderMethod {
        case "cash", "check":
            return true
        default:
            return false
        }
    }
}
#endif
