import Foundation

// MARK: - CSVComposer (RFC-4180)

/// Produces RFC-4180 compliant CSV strings.
/// - Fields containing commas, newlines, or double-quotes are wrapped in double-quotes.
/// - Double-quotes inside a field are escaped as two consecutive double-quotes ("").
/// - Records are separated by CRLF (\r\n).
/// - The header row (if provided via `columns`) is always the first record.
public enum CSVComposer {

    /// Compose a CSV string from column headers and data rows.
    /// - Parameters:
    ///   - rows: Each inner array is one record; values correspond positionally to `columns`.
    ///   - columns: Column header names written as the first record.
    /// - Returns: A UTF-8 CSV string conforming to RFC-4180.
    public static func compose(rows: [[String]], columns: [String]) -> String {
        var records: [[String]] = [columns]
        records.append(contentsOf: rows)
        return records
            .map { record in record.map(escapeField).joined(separator: ",") }
            .joined(separator: "\r\n")
    }

    // MARK: - Internal

    /// Wraps a field in double-quotes if it contains a comma, newline, or double-quote.
    /// Double-quotes inside the field are doubled per RFC-4180 §2.7.
    static func escapeField(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\r") ||
                           value.contains("\n") || value.contains("\"")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
