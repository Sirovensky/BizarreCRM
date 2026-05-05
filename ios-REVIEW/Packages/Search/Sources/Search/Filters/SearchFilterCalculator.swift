import Foundation

/// §18.7 — Pure stateless query builder. No network, no GRDB, fully testable.
public enum SearchFilterCalculator {

    /// Build an FTS5 MATCH expression from a base query + filter set.
    ///
    /// The resulting string is safe to pass to `FTSIndexStore.search(query:entity:)`.
    /// `entity` in `filters` drives the entity-column restriction but is
    /// NOT embedded into the query string — the caller passes it separately.
    ///
    /// Appended constraints use AND to narrow results:
    /// - `status` → AND tags:\(status)*
    /// - `dateFrom` / `dateTo` → not embeddable in FTS5 body; returned as
    ///   separate `DateRange` output so callers can post-filter.
    public static func buildQuery(base: String, filters: SearchFilters) -> QueryResult {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        if let status = filters.status, !status.isEmpty {
            let safeStatus = status.replacingOccurrences(of: "\"", with: "\"\"")
            parts.append("tags:\"\(safeStatus)\"*")
        }

        let ftsQuery = parts.joined(separator: " AND ")
        return QueryResult(
            ftsQuery: ftsQuery,
            entityFilter: filters.entity,
            dateFrom: filters.dateFrom,
            dateTo: filters.dateTo
        )
    }

    // MARK: - Result

    public struct QueryResult: Sendable {
        /// The FTS5 MATCH expression.
        public let ftsQuery: String
        /// Entity scope to pass to `FTSIndexStore`.
        public let entityFilter: EntityFilter
        /// Optional post-filter: hits before this date should be excluded.
        public let dateFrom: Date?
        /// Optional post-filter: hits after this date should be excluded.
        public let dateTo: Date?

        public var isEmpty: Bool { ftsQuery.isEmpty }
    }
}
