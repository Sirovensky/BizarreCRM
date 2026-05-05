import Foundation

/// Pure function namespace for converting `[AuditLogEntry]` → RFC-4180 CSV string.
///
/// Column order (stable, §50):
///   id, created_at, actor_name, actor_user_id, action, entity_kind, entity_id, metadata
///
/// RFC-4180 rules applied:
/// - Fields containing commas, double-quotes, or newlines are wrapped in double-quotes.
/// - Double-quote characters inside a quoted field are escaped as `""`.
/// - Line endings are CRLF as required by RFC-4180.
/// - First row is always the header.
public enum AuditLogCSVComposer {

    // MARK: - Public interface

    /// Column headers in stable, RFC-4180-compliant order.
    public static let columnHeaders: [String] = [
        "id",
        "created_at",
        "actor_name",
        "actor_user_id",
        "action",
        "entity_kind",
        "entity_id",
        "metadata"
    ]

    /// Convert an array of entries to an RFC-4180 CSV string.
    ///
    /// - Parameters:
    ///   - entries: Entries to serialise; may be empty (returns header-only CSV).
    ///   - since: Optional lower bound (inclusive) for `createdAt` date-range filter.
    ///   - until: Optional upper bound (inclusive) for `createdAt` date-range filter.
    ///   - dateFormatter: ISO-8601 formatter used for the `created_at` column.
    ///     Defaults to `yyyy-MM-dd'T'HH:mm:ssXXXXX`.
    /// - Returns: A complete RFC-4180 CSV string with CRLF line endings.
    public static func compose(
        entries: [AuditLogEntry],
        since: Date? = nil,
        until: Date? = nil,
        dateFormatter: DateFormatter = Self.iso8601Formatter
    ) -> String {
        let filtered = entries.filter { entry in
            if let since, entry.createdAt < since { return false }
            if let until, entry.createdAt > until { return false }
            return true
        }

        var lines: [String] = []
        lines.reserveCapacity(filtered.count + 1)

        // Header row
        lines.append(row(from: columnHeaders))

        // Data rows
        for entry in filtered {
            lines.append(row(from: fields(for: entry, dateFormatter: dateFormatter)))
        }

        // RFC-4180: CRLF line endings, including trailing CRLF after the last record.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Internal helpers (internal so tests can reach them)

    /// Build the ordered field values for one entry.
    static func fields(
        for entry: AuditLogEntry,
        dateFormatter: DateFormatter = Self.iso8601Formatter
    ) -> [String] {
        [
            entry.id,
            dateFormatter.string(from: entry.createdAt),
            entry.actorName,
            entry.actorUserId.map(String.init) ?? "",
            entry.action,
            entry.entityKind,
            entry.entityId.map(String.init) ?? "",
            metadataString(from: entry.metadata)
        ]
    }

    /// Assemble one CSV row from an array of field values.
    /// Each field is quoted-escaped per RFC-4180 as needed.
    static func row(from values: [String]) -> String {
        values.map { escape($0) }.joined(separator: ",")
    }

    /// RFC-4180 field escaping:
    /// - If the value contains a comma, double-quote, CR, or LF → wrap in `"…"`
    ///   and replace every `"` inside with `""`.
    /// - Otherwise return the value as-is.
    static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\r")
            || value.contains("\n")

        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Convert the metadata dict to a compact JSON-like string suitable for a CSV cell.
    /// Uses sorted keys for stability across calls.
    static func metadataString(from metadata: [String: AuditDiffValue]?) -> String {
        guard let metadata, !metadata.isEmpty else { return "" }
        let pairs = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.displayString)" }
            .joined(separator: "; ")
        return pairs
    }

    // MARK: - Date formatter

    /// Default ISO-8601 formatter (`yyyy-MM-dd'T'HH:mm:ssXXXXX`).
    public static let iso8601Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
