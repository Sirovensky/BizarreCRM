import Foundation
import GRDB
import Core

/// §39 — local-first cash register sessions.
///
/// Server endpoints `POST /pos/cash-sessions` and `POST /pos/cash-sessions/:id/close`
/// are not wired yet (see `docs/ios-api-gap-audit.md` ticket `POS-SESSIONS-001`).
/// Until they ship, sessions live exclusively on-device and enqueue payloads
/// to `sync_queue` under `entity: "cash_session"` so replay is available the
/// moment the server catches up.
///
/// Invariant: at most one open session per device+user at a time. `openSession`
/// returns `CashRegisterError.alreadyOpen` instead of raising a raw SQLite
/// constraint error so UI can render a friendly "session already open" card.
public struct CashSessionRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "cash_sessions"

    public var id: Int64?
    public var openedBy: Int64
    public var openedAt: Date
    public var openingFloat: Int            // cents
    public var closedAt: Date?
    public var closedBy: Int64?
    public var countedCash: Int?            // cents
    public var expectedCash: Int?           // cents
    public var varianceCents: Int?
    public var notes: String?
    public var serverId: String?
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case openedBy       = "opened_by"
        case openedAt       = "opened_at"
        case openingFloat   = "opening_float"
        case closedAt       = "closed_at"
        case closedBy       = "closed_by"
        case countedCash    = "counted_cash"
        case expectedCash   = "expected_cash"
        case varianceCents  = "variance_cents"
        case notes
        case serverId       = "server_id"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    public init(
        id: Int64? = nil,
        openedBy: Int64,
        openedAt: Date,
        openingFloat: Int,
        closedAt: Date? = nil,
        closedBy: Int64? = nil,
        countedCash: Int? = nil,
        expectedCash: Int? = nil,
        varianceCents: Int? = nil,
        notes: String? = nil,
        serverId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.openedBy = openedBy
        self.openedAt = openedAt
        self.openingFloat = openingFloat
        self.closedAt = closedAt
        self.closedBy = closedBy
        self.countedCash = countedCash
        self.expectedCash = expectedCash
        self.varianceCents = varianceCents
        self.notes = notes
        self.serverId = serverId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// `true` if the session is still open (no closed_at stamp).
    public var isOpen: Bool { closedAt == nil }

    /// GRDB hook — attach the AUTOINCREMENT `rowID` back onto the local
    /// struct so the caller of `openSession` gets a populated `id` field.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum CashRegisterError: Error, LocalizedError, Sendable {
    case alreadyOpen
    case noOpenSession
    case databaseUnavailable

    public var errorDescription: String? {
        switch self {
        case .alreadyOpen:          return "A cash session is already open — close it before opening another."
        case .noOpenSession:        return "No open cash session to close."
        case .databaseUnavailable:  return "Local database is not ready."
        }
    }
}

public actor CashRegisterStore {
    public static let shared = CashRegisterStore()
    private init() {}

    /// Open a new session. Fails if an open session already exists.
    @discardableResult
    public func openSession(openingFloat: Int, userId: Int64, at date: Date = Date()) async throws -> CashSessionRecord {
        guard let pool = await Database.shared.pool() else {
            throw CashRegisterError.databaseUnavailable
        }
        return try await pool.write { db in
            let existing = try CashSessionRecord
                .filter(Column("closed_at") == nil)
                .fetchOne(db)
            if existing != nil {
                throw CashRegisterError.alreadyOpen
            }
            var record = CashSessionRecord(
                openedBy: userId,
                openedAt: date,
                openingFloat: max(0, openingFloat),
                createdAt: date,
                updatedAt: date
            )
            try record.insert(db)
            // `insert` runs `didInsert` which stamps the rowID onto
            // `record.id` so the caller can round-trip straight to a
            // `session(id:)` lookup without a second read.
            AppLog.pos.info("cash_session opened id=\(record.id ?? -1) float=\(record.openingFloat)")
            return record
        }
    }

    /// The currently-open session, or `nil` if the register is closed.
    public func currentSession() async throws -> CashSessionRecord? {
        guard let pool = await Database.shared.pool() else { return nil }
        return try await pool.read { db in
            try CashSessionRecord
                .filter(Column("closed_at") == nil)
                .order(Column("opened_at").desc)
                .fetchOne(db)
        }
    }

    /// Fetch a session by primary key. Used by the close flow and Z-report
    /// view to replay a just-closed session.
    public func session(id: Int64) async throws -> CashSessionRecord? {
        guard let pool = await Database.shared.pool() else { return nil }
        return try await pool.read { db in
            try CashSessionRecord.filter(Column("id") == id).fetchOne(db)
        }
    }

    /// Close the currently-open session. Returns the updated record so the
    /// Z-report view can consume it immediately without a second read.
    ///
    /// `expectedCash` is what the register *should* have at close based on
    /// the opening float plus any cash-in / cash-out / cash-tender activity.
    /// The caller (typically `CloseRegisterSheet`) computes this so the
    /// store stays pure-storage and doesn't need to know about invoices.
    @discardableResult
    public func closeSession(
        countedCash: Int,
        expectedCash: Int,
        notes: String?,
        closedBy: Int64,
        at date: Date = Date()
    ) async throws -> CashSessionRecord {
        guard let pool = await Database.shared.pool() else {
            throw CashRegisterError.databaseUnavailable
        }
        return try await pool.write { db in
            guard var row = try CashSessionRecord
                .filter(Column("closed_at") == nil)
                .order(Column("opened_at").desc)
                .fetchOne(db) else {
                throw CashRegisterError.noOpenSession
            }
            row.closedAt = date
            row.closedBy = closedBy
            row.countedCash = countedCash
            row.expectedCash = expectedCash
            row.varianceCents = countedCash - expectedCash
            row.notes = notes
            row.updatedAt = date
            try row.update(db)
            AppLog.pos.info("cash_session closed id=\(row.id ?? -1) variance=\(row.varianceCents ?? 0)")
            return row
        }
    }

    /// Recent sessions ordered newest-first. Drives the shift history UI
    /// (not shipped in this PR but the store exposes it so a list screen
    /// can land without a schema change).
    public func recentSessions(limit: Int = 20) async throws -> [CashSessionRecord] {
        guard let pool = await Database.shared.pool() else { return [] }
        return try await pool.read { db in
            try CashSessionRecord
                .order(Column("opened_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Stamp the server-assigned id onto a local row once the sync replay
    /// lands. Called from the `cash_session.create` sync handler.
    public func markSynced(localId: Int64, serverId: String) async throws {
        guard let pool = await Database.shared.pool() else { return }
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE cash_sessions SET server_id = ?, updated_at = ? WHERE id = ?",
                arguments: [serverId, Date(), localId]
            )
        }
    }
}
