import Foundation

// MARK: - CSVRowParser

/// Parses RFC-4180-compatible CSV text into rows of fields.
/// Handles: quoted fields, embedded commas, embedded newlines, escaped quotes ("").
/// Operates on Unicode scalars to correctly handle CRLF (which Swift's Character
/// type merges into a single grapheme cluster).
public enum CSVRowParser {

    // MARK: - Public API

    /// Parse full CSV text into an array of rows (each row is an array of fields).
    /// - Parameter text: Raw CSV text.
    /// - Returns: Array of rows; first row is typically the header.
    public static func parse(_ text: String) -> [[String]] {
        // Work at the Unicode scalar level so that \r\n (a single Swift Character
        // grapheme cluster) is seen as two distinct code points.
        let scalars = Array(text.unicodeScalars)
        let count = scalars.count

        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = 0

        func advance() { i += 1 }
        func peek() -> Unicode.Scalar? { i + 1 < count ? scalars[i + 1] : nil }

        func flushField() {
            current.append(field)
            field = ""
        }

        func flushRow() {
            if !current.isEmpty {
                rows.append(current)
            }
            current = []
        }

        while i < count {
            let sc = scalars[i]

            if inQuotes {
                if sc == "\"" {
                    if let next = peek(), next == "\"" {
                        // Escaped double-quote inside quoted field
                        field.append("\"")
                        advance() // skip first "
                        advance() // skip second "
                    } else {
                        inQuotes = false
                        advance()
                    }
                } else {
                    // Append scalar as character to field
                    field.append(Character(sc))
                    advance()
                }
            } else {
                switch sc {
                case "\"":
                    inQuotes = true
                    advance()
                case ",":
                    flushField()
                    advance()
                case "\r":
                    // CR or CRLF — consume both if \n follows
                    advance()
                    if i < count, scalars[i] == "\n" {
                        advance()
                    }
                    flushField()
                    flushRow()
                case "\n":
                    advance()
                    flushField()
                    flushRow()
                default:
                    field.append(Character(sc))
                    advance()
                }
            }
        }

        // Flush trailing field / row
        current.append(field)
        if current.contains(where: { !$0.isEmpty }) { rows.append(current) }

        return rows
    }

    /// Convenience: returns (headers, dataRows) where headers is row[0].
    /// Returns ([], []) for empty input.
    public static func parseWithHeaders(_ text: String) -> (headers: [String], rows: [[String]]) {
        let all = parse(text)
        guard !all.isEmpty else { return ([], []) }
        return (all[0], Array(all.dropFirst()))
    }
}
