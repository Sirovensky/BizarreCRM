import Foundation

/// §18.8 — Strip SSN / tax-ID-shaped digit runs out of any string before it
/// is committed to the FTS5 search index.
///
/// The server hashes these fields server-side, but free-form `customer.notes`
/// can occasionally contain them when staff paste from another system. This
/// scrubber is a defence-in-depth pass so the local SQLCipher index never
/// stores or returns a raw SSN / EIN as a search hit.
///
/// Patterns redacted (case-insensitive, non-greedy):
/// * US SSN — `\d{3}-\d{2}-\d{4}` → `[redacted]`
/// * US EIN / federal tax-ID — `\d{2}-\d{7}` → `[redacted]`
/// * Bare 9-digit run preceded by SSN/Tax/EIN keyword on the same line.
public enum SensitiveDataScrubber {

    private static let patterns: [NSRegularExpression] = {
        let raws = [
            #"\b\d{3}-\d{2}-\d{4}\b"#,                  // SSN
            #"\b\d{2}-\d{7}\b"#,                         // EIN
            #"(?i)\b(?:ssn|ein|tax[-\s]?id)\b[^\d]{0,8}\d{9}\b"# // keyword + 9 digits
        ]
        return raws.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Returns `text` with every SSN / EIN / tax-ID pattern replaced by
    /// `[redacted]`. Idempotent and safe for empty input.
    public static func scrub(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for regex in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[redacted]"
            )
        }
        return result
    }
}
