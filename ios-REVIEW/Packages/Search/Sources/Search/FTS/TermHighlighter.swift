import SwiftUI

/// §18 — Highlights query terms inside a display string, returning an
/// `AttributedString` where matched tokens are bolded with the brand accent colour.
///
/// Matching is case-insensitive and diacritic-insensitive. Accepts the raw
/// FTS5 snippet string (which already embeds `<b>…</b>` markers from
/// `snippet()`) as well as plain strings.
public enum TermHighlighter {

    // MARK: - FTS5 snippet → AttributedString

    /// Parse an FTS5 snippet that uses `<b>…</b>` as highlight markers.
    /// Falls back to `highlight(text:query:)` when no markers are present.
    public static func attributed(snippet: String, highlightColor: Color = .orange) -> AttributedString {
        guard snippet.contains("<b>") else {
            return AttributedString(snippet)
        }
        var result = AttributedString()
        var remaining = snippet[...]

        while !remaining.isEmpty {
            if let openRange = remaining.range(of: "<b>"),
               let closeRange = remaining.range(of: "</b>", range: openRange.upperBound ..< remaining.endIndex) {
                // Append plain prefix
                let plainPart = String(remaining[remaining.startIndex ..< openRange.lowerBound])
                if !plainPart.isEmpty {
                    result.append(AttributedString(plainPart))
                }
                // Append highlighted part
                let highlightedText = String(remaining[openRange.upperBound ..< closeRange.lowerBound])
                var highlighted = AttributedString(highlightedText)
                highlighted.foregroundColor = highlightColor
                highlighted.font = .body.bold()
                result.append(highlighted)
                remaining = remaining[closeRange.upperBound...]
            } else {
                // No more markers — append the rest as plain text.
                result.append(AttributedString(String(remaining)))
                break
            }
        }
        return result
    }

    // MARK: - Plain text + query terms → AttributedString

    /// Highlight all occurrences of each whitespace-separated token from
    /// `query` inside `text`. Case- and diacritic-insensitive.
    public static func highlight(
        text: String,
        query: String,
        highlightColor: Color = .orange
    ) -> AttributedString {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return AttributedString(text) }

        var result = AttributedString(text)

        for token in tokens {
            var searchFrom = result.startIndex
            while searchFrom < result.endIndex {
                guard let range = result[searchFrom...].range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) else { break }
                result[range].foregroundColor = highlightColor
                result[range].font = .body.bold()
                searchFrom = range.upperBound
            }
        }
        return result
    }
}
