import Foundation
import GRDB
import Core

// MARK: - PosAuditEntry

/// A single loss-prevention audit event persisted to the local DB.
///
/// All money fields are in integer cents to avoid floating-point drift.
/// `contextJson` is a raw JSON string; callers decode it themselves because
/// the shape is event-type-specific (see `005_pos_audit_log.sql` for the
/// canonical key listing).
public struct PosAuditEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "pos_audit_entries"

    public var id: Int64?
    /// One of: 'void_line', 'no_sale', 'discount_override', 'price_override', 'delete_line'
    public var eventType: String
    /// Cashier who performed the action. 0 = placeholder until auth/me ships.
    public var cashierId: Int64
    /// Manager who approved the action, or nil when cashier stayed under threshold.
    public var managerId: Int64?
    /// Price delta, discount amount, or line value in cents; nil when not applicable.
    public var amountCents: Int?
    /// Free-form reason entered by the cashier or manager.
    public var reason: String?
    /// JSON blob with event-specific detail (sku, lineName, originalPriceCents, …).
    public var contextJson: String?
    /// Creation timestamp — Unix seconds stored as REAL for sub-second precision.
    public var createdAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id
        case eventType   = "event_type"
        case cashierId   = "cashier_id"
        case managerId   = "manager_id"
        case amountCents = "amount_cents"
        case reason
        case contextJson = "context_json"
        case createdAt   = "created_at"
    }

    public init(
        id: Int64? = nil,
        eventType: String,
        cashierId: Int64,
        managerId: Int64? = nil,
        amountCents: Int? = nil,
        reason: String? = nil,
        contextJson: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.eventType = eventType
        self.cashierId = cashierId
        self.managerId = managerId
        self.amountCents = amountCents
        self.reason = reason
        self.contextJson = contextJson
        self.createdAt = createdAt
    }

    /// GRDB hook — stamps AUTOINCREMENT rowID back onto the struct after insert
    /// so the caller's returned id is immediately valid.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Convenience: decode `contextJson` into a `[String: String]` dictionary.
    /// Returns an empty dict on any parse failure so callsites need no guard.
    public var contextDictionary: [String: String] {
        guard let raw = contextJson,
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return parsed.reduce(into: [:]) { acc, pair in
            if let v = pair.value as? CustomStringConvertible {
                acc[pair.key] = String(describing: v)
            }
        }
    }

    /// Human-readable label for the event type badge in the audit log UI.
    public var eventTypeLabel: String {
        switch eventType {
        case "void_line":           return "Void line"
        case "no_sale":             return "No sale"
        case "discount_override":   return "Discount override"
        case "price_override":      return "Price override"
        case "delete_line":         return "Delete line"
        default:                    return eventType
        }
    }

    /// Date representation of `createdAt` for display and grouping.
    public var date: Date { Date(timeIntervalSince1970: createdAt) }
}

// MARK: - Known event types

public extension PosAuditEntry {
    enum EventType {
        public static let voidLine          = "void_line"
        public static let noSale            = "no_sale"
        public static let discountOverride  = "discount_override"
        public static let priceOverride     = "price_override"
        public static let deleteLine        = "delete_line"
    }
}

// MARK: - PosAuditLogStore

/// Local-first, append-only store for POS loss-prevention audit events.
///
/// Thread-safety: `actor` isolation — all reads and writes are serialised
/// through the actor's executor and then further through GRDB's pool.
///
/// Relationship to §39 `CashRegisterStore`: independent table, same DB pool.
/// The audit log is NOT cleared on register close; it accumulates per device
/// and can be viewed at any time via `PosAuditLogView`.
public actor PosAuditLogStore {
    public static let shared = PosAuditLogStore()
    private init() {}

    // MARK: - Write

    /// Append one audit event and return its auto-assigned primary key.
    ///
    /// - Parameters:
    ///   - event:       One of `PosAuditEntry.EventType.*` constants.
    ///   - cashierId:   The acting cashier. Pass 0 until auth/me ships.
    ///   - managerId:   The approving manager, or nil.
    ///   - amountCents: Money delta in cents, nil when not applicable.
    ///   - reason:      Free-form text from the cashier / manager prompt.
    ///   - context:     JSON-serialisable dictionary for event-specific detail.
    /// - Returns: The inserted row's primary key.
    @discardableResult
    public func record(
        event: String,
        cashierId: Int64,
        managerId: Int64? = nil,
        amountCents: Int? = nil,
        reason: String? = nil,
        context: [String: Any] = [:]
    ) async throws -> Int64 {
        guard let pool = await Database.shared.pool() else {
            throw AuditLogError.databaseUnavailable
        }
        let contextJson: String? = context.isEmpty ? nil : {
            guard let data = try? JSONSerialization.data(withJSONObject: context),
                  let str = String(data: data, encoding: .utf8)
            else { return nil }
            return str
        }()

        // Swift 6: GRDB's write closure is @Sendable so we cannot capture a
        // `var` that mutates inside it. Workaround: perform the insert inside
        // the closure and return the rowID from it.
        let rowId: Int64 = try await pool.write { db in
            var entry = PosAuditEntry(
                eventType: event,
                cashierId: cashierId,
                managerId: managerId,
                amountCents: amountCents,
                reason: reason,
                contextJson: contextJson
            )
            try entry.insert(db)
            return entry.id ?? -1
        }
        AppLog.pos.info("audit event=\(event) id=\(rowId) cashier=\(cashierId) manager=\(managerId ?? -1)")
        return rowId
    }

    // MARK: - Read

    /// Return up to `limit` entries, newest first.
    public func recent(limit: Int = 50) async throws -> [PosAuditEntry] {
        guard let pool = await Database.shared.pool() else { return [] }
        return try await pool.read { db in
            try PosAuditEntry
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Return up to `limit` entries for a specific event type, newest first.
    public func byEventType(_ type: String, limit: Int = 50) async throws -> [PosAuditEntry] {
        guard let pool = await Database.shared.pool() else { return [] }
        return try await pool.read { db in
            try PosAuditEntry
                .filter(Column("event_type") == type)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Count entries for a given event type in a date range.
    /// Used by `ZReportAggregates.from(auditEntries:)` and the loss-prevention tile.
    public func count(eventType: String, from: Date, to: Date) async throws -> Int {
        guard let pool = await Database.shared.pool() else { return 0 }
        return try await pool.read { db in
            try PosAuditEntry
                .filter(Column("event_type") == eventType)
                .filter(Column("created_at") >= from.timeIntervalSince1970)
                .filter(Column("created_at") <= to.timeIntervalSince1970)
                .fetchCount(db)
        }
    }
}

// MARK: - Errors

public enum AuditLogError: Error, LocalizedError, Sendable {
    case databaseUnavailable

    public var errorDescription: String? {
        "Local database is not ready — audit event could not be saved."
    }
}
