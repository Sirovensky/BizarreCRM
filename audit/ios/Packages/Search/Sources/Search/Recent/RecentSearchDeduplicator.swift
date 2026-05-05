import Foundation

// MARK: - RecentSearchDeduplicator

/// Pure-logic helper that normalises and deduplicates a list of recent-search
/// queries before they are persisted or displayed.
///
/// Rules applied in order:
/// 1. **Trim** leading/trailing whitespace.
/// 2. **Drop empty** strings.
/// 3. **Case-insensitive dedup** — the first (most-recent) casing wins.
/// 4. **Collapse whitespace** — interior runs of whitespace reduced to a single space.
/// 5. **Length cap** — queries longer than `maxQueryLength` chars are truncated.
/// 6. **Count cap** — final list is capped at `maxCount` entries.
///
/// All methods are `static`; the type is stateless and `Sendable`.
public enum RecentSearchDeduplicator {

    // MARK: - Tunables

    /// Maximum number of saved recent queries. Default: 20.
    public static let maxCount: Int = 20

    /// Maximum number of characters in a stored query. Longer queries are truncated.
    public static let maxQueryLength: Int = 120

    // MARK: - Public API

    /// Deduplicate, normalise, and cap `queries`.
    ///
    /// - Parameter queries: An ordered list of queries, most-recent first.
    /// - Returns: A cleaned list ready for persistence or display.
    public static func deduplicate(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for raw in queries {
            let normalised = normalise(raw)
            guard !normalised.isEmpty else { continue }
            let key = normalised.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(normalised)
            if result.count >= maxCount { break }
        }
        return result
    }

    /// Prepend `query` to `existing`, then deduplicate and cap.
    ///
    /// Equivalent to `deduplicate([query] + existing)` but slightly more efficient
    /// since it avoids copying the entire array before filtering.
    ///
    /// - Parameters:
    ///   - query: The new query being added (most-recent, goes to index 0).
    ///   - existing: The current persisted list, most-recent first.
    /// - Returns: Updated list with `query` at position 0 and no duplicates.
    public static func prepending(_ query: String, to existing: [String]) -> [String] {
        deduplicate([query] + existing)
    }

    /// Remove the first occurrence of `query` (case-insensitive) from `queries`.
    public static func removing(_ query: String, from queries: [String]) -> [String] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return queries.filter { $0.lowercased() != key }
    }

    // MARK: - Normalisation

    /// Normalise a raw query string.
    ///
    /// - Trims whitespace.
    /// - Collapses internal whitespace runs to a single space.
    /// - Truncates to `maxQueryLength` characters (on a `Character` boundary).
    public static func normalise(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Collapse internal whitespace
        let collapsed = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Truncate if needed (on Character boundary to avoid broken multi-byte sequences)
        if collapsed.count > maxQueryLength {
            return String(collapsed.prefix(maxQueryLength))
        }
        return collapsed
    }
}
