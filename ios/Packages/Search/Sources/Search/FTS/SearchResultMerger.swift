import Foundation

/// §18.7 — Merges local FTS5 hits with remote server `GlobalSearchResults`.
///
/// Strategy:
/// 1. Local hits appear first (sub-200ms offline fast lane).
/// 2. Remote rows that share an (entity, id) with a local hit are deduped —
///    the local hit is kept because it carries a highlighted snippet.
/// 3. Remaining remote rows are appended in server-provided order.
/// 4. If the server result arrives first (edge case), it is used as-is.
///
/// Filtering by `EntityFilter` is applied before returning so both local and
/// remote sections respect the currently active scope chip.
public enum SearchResultMerger {

    /// Unified result row — wraps either a local `SearchHit` or a remote row.
    public enum MergedRow: Identifiable, Sendable {
        /// Came from the local FTS5 index (fast lane). Carries a highlighted snippet.
        case local(SearchHit)
        /// Came from the server; no pre-highlighted snippet.
        case remote(GlobalSearchResults.Row, entity: String)

        public var id: String {
            switch self {
            case .local(let hit):           return "local:\(hit.entity):\(hit.entityId)"
            case .remote(let row, let ent): return "remote:\(ent):\(row.id)"
            }
        }

        public var entity: String {
            switch self {
            case .local(let hit):      return hit.entity
            case .remote(_, let ent):  return ent
            }
        }

        public var entityId: String {
            switch self {
            case .local(let hit):      return hit.entityId
            case .remote(let row, _):  return String(row.id)
            }
        }

        /// Display title — local title, or remote `display`.
        public var title: String {
            switch self {
            case .local(let hit):   return hit.title
            case .remote(let row, _): return row.display ?? ""
            }
        }

        /// Highlighted snippet — available from local only.
        public var snippet: String? {
            switch self {
            case .local(let hit): return hit.snippet.isEmpty ? nil : hit.snippet
            case .remote:         return nil
            }
        }

        public var subtitle: String? {
            switch self {
            case .local:              return nil
            case .remote(let row, _): return row.subtitle
            }
        }
    }

    // MARK: - Merge

    /// Merge local + remote results applying the given entity scope.
    ///
    /// - Parameters:
    ///   - localHits:  Results from `FTSIndexStore.search(...)`.
    ///   - remote:     Response from `APIClient.globalSearch(...)`, or `nil`
    ///                 when the server hasn't responded yet.
    ///   - filter:     Active `EntityFilter`; `.all` disables filtering.
    /// - Returns:      Merged, deduped, filtered rows.
    public static func merge(
        localHits: [SearchHit],
        remote: GlobalSearchResults?,
        filter: EntityFilter
    ) -> [MergedRow] {
        // Build a de-dup key set from local hits (entity + entityId).
        var localKeys = Set<String>()
        var rows: [MergedRow] = []

        // 1. Local hits first.
        for hit in localHits {
            guard passes(entity: hit.entity, filter: filter) else { continue }
            localKeys.insert(dedupeKey(entity: hit.entity, id: hit.entityId))
            rows.append(.local(hit))
        }

        // 2. Remote rows that are NOT already covered by local hits.
        guard let remote else { return rows }

        let remotePairs: [(entity: String, row: GlobalSearchResults.Row)] =
            remote.customers.map   { ("customers",    $0) } +
            remote.tickets.map     { ("tickets",      $0) } +
            remote.inventory.map   { ("inventory",    $0) } +
            remote.invoices.map    { ("invoices",     $0) }

        for (entity, row) in remotePairs {
            guard passes(entity: entity, filter: filter) else { continue }
            let key = dedupeKey(entity: entity, id: String(row.id))
            guard !localKeys.contains(key) else { continue }
            rows.append(.remote(row, entity: entity))
        }

        return rows
    }

    // MARK: - Helpers

    private static func dedupeKey(entity: String, id: String) -> String {
        "\(entity):\(id)"
    }

    private static func passes(entity: String, filter: EntityFilter) -> Bool {
        guard filter != .all else { return true }
        return entity == filter.rawValue
    }
}
