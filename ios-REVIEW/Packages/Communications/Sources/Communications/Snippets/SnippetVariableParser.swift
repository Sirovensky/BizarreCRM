import Foundation

// MARK: - SnippetVariableParser

/// Pure, stateless utility for `{{variable}}` substitution in SMS snippets.
/// Snippets use double-brace syntax: `{{first_name}}`, `{{company}}`, etc.
public enum SnippetVariableParser: Sendable {

    // MARK: - Extract

    /// Returns every `{{var}}` token found in `text` (deduplicated, preserving order).
    public static func extract(from text: String) -> [String] {
        let pattern = "\\{\\{[a-zA-Z_]+\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range, in: text) {
                let token = String(text[r])
                if seen.insert(token).inserted { result.append(token) }
            }
        }
        return result
    }

    // MARK: - Render

    /// Substitutes known tokens with the supplied map. Unknown tokens are left as-is.
    public static func render(_ text: String, variables: [String: String]) -> String {
        var result = text
        for (token, value) in variables {
            // Normalise token: accept both `first_name` and `{{first_name}}`.
            let key = token.hasPrefix("{{") ? token : "{{\(token)}}"
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    // MARK: - Sample preview

    private static let sampleValues: [String: String] = [
        "{{first_name}}": "Jane",
        "{{last_name}}": "Smith",
        "{{company}}": "Acme Corp",
        "{{ticket_no}}": "TKT-0042",
        "{{amount}}": "$149.99",
        "{{date}}": DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none),
        "{{phone}}": "+1 (555) 867-5309"
    ]

    /// Returns a preview string with sample values for all recognised tokens.
    public static func renderSample(_ text: String) -> String {
        render(text, variables: sampleValues)
    }
}
