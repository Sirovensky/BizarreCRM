import Foundation
import GRDB
import Core

/// §18.3 — Public FTS5 façade. Index entity objects; run typed searches.
///
/// All methods are `async throws` and serialised through the underlying
/// `FTSIndex` actor.  Callers never touch GRDB directly.
public actor FTSIndexStore {

    // MARK: - Properties

    private let index: FTSIndex

    // MARK: - Init

    /// Production init — pass the shared `DatabasePool` (or `DatabaseQueue`).
    public init(db: any DatabaseWriter) {
        self.index = FTSIndex(db: db)
    }

    /// Convenience factory that opens the **isolated** App Group FTS database
    /// and returns a ready-to-use `FTSIndexStore`. Use this at app launch
    /// instead of threading the main Persistence `DatabasePool` through.
    ///
    /// - Parameter appGroupIdentifier: The App Group ID.
    ///   Pass `nil` to use the production default `"group.com.bizarrecrm"`.
    public static func isolated(
        appGroupIdentifier: String = "group.com.bizarrecrm"
    ) throws -> FTSIndexStore {
        let queue = try IsolatedFTSDatabase.open(appGroupIdentifier: appGroupIdentifier)
        return FTSIndexStore(db: queue)
    }

    // MARK: - Indexing

    public func indexTicket(_ ticket: Ticket) async throws {
        let row = FTSIndex.IndexRow(
            entity:    "tickets",
            entityId:  String(ticket.id),
            title:     "\(ticket.displayId) \(ticket.customerName)",
            body:      [ticket.deviceSummary, ticket.diagnosis, ticket.status.rawValue]
                           .compactMap { $0 }.joined(separator: " "),
            tags:      ticket.status.rawValue,
            updatedAt: ISO8601DateFormatter().string(from: ticket.updatedAt)
        )
        try index.upsert(row)
    }

    public func indexCustomer(_ customer: Customer) async throws {
        let row = FTSIndex.IndexRow(
            entity:    "customers",
            entityId:  String(customer.id),
            title:     customer.displayName,
            body:      [customer.phone, customer.email, customer.notes]
                           .compactMap { $0 }.joined(separator: " "),
            tags:      "",
            updatedAt: ISO8601DateFormatter().string(from: customer.updatedAt)
        )
        try index.upsert(row)
    }

    public func indexInventory(_ item: InventoryItem) async throws {
        let row = FTSIndex.IndexRow(
            entity:    "inventory",
            entityId:  String(item.id),
            title:     item.name,
            body:      [item.sku, item.barcode].compactMap { $0 }.joined(separator: " "),
            tags:      item.sku,
            updatedAt: ISO8601DateFormatter().string(from: item.updatedAt)
        )
        try index.upsert(row)
    }

    /// Index a generic invoice using plain string fields (no Invoice model in Core yet).
    public func indexInvoice(id: Int64, displayId: String, customerName: String, updatedAt: Date) async throws {
        let row = FTSIndex.IndexRow(
            entity:    "invoices",
            entityId:  String(id),
            title:     "\(displayId) \(customerName)",
            body:      customerName,
            tags:      "",
            updatedAt: ISO8601DateFormatter().string(from: updatedAt)
        )
        try index.upsert(row)
    }

    // MARK: - Search

    /// Run an FTS5 query. Returns up to `limit` results sorted by relevance.
    public func search(
        query: String,
        entity filter: EntityFilter? = nil,
        limit: Int = 50
    ) async throws -> [SearchHit] {
        let entityValue: String? = (filter == nil || filter == .all) ? nil : filter?.rawValue
        let raw = try index.search(query: query, entityFilter: entityValue, limit: limit)
        return raw.map { hit in
            SearchHit(
                entity:   hit.entity,
                entityId: hit.entityId,
                title:    hit.title,
                snippet:  hit.snippet,
                score:    hit.rank
            )
        }
    }

    // MARK: - Scope counts

    /// Return per-entity hit counts for `query` across all entity types.
    /// Used to populate count badges on scope filter chips.
    public func scopeCounts(query: String) async throws -> ScopeCounts {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .zero
        }
        let allHits = try index.search(query: query, entityFilter: nil, limit: 200)
        let searchHits = allHits.map { raw in
            SearchHit(
                entity:   raw.entity,
                entityId: raw.entityId,
                title:    raw.title,
                snippet:  raw.snippet,
                score:    raw.rank
            )
        }
        return ScopeCounts.from(localHits: searchHits)
    }

    // MARK: - Delete

    public func deleteEntity(_ entity: String, _ id: String) async throws {
        try index.delete(entity: entity, entityId: id)
    }
}
