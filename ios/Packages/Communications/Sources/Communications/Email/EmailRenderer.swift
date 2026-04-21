import Foundation

// MARK: - EmailRenderer

/// Pure, stateless renderer for email templates.
/// Substitutes `{var_name}` placeholders in subject, htmlBody, and plainBody.
/// When `plainBody` is nil on the template, derives plain text by stripping HTML tags
/// from the rendered htmlBody.
public enum EmailRenderer: Sendable {

    // MARK: - Known vars / sample context

    /// Sample context for live-preview use.
    public static let sampleContext: [String: String] = [
        "first_name":       "Jane",
        "last_name":        "Smith",
        "ticket_no":        "TKT-0042",
        "total":            "$149.99",
        "due_date":         "May 5, 2026",
        "tech_name":        "Alex T.",
        "appointment_time": "Mon Apr 28 at 2:00 PM",
        "shop_name":        "Bizarre CRM Demo",
        "company":          "Acme Corp",
        "amount":           "$149.99",
        "date":             "Apr 28, 2026",
    ]

    // MARK: - Render result

    public struct Rendered: Sendable {
        public let subject: String
        public let html: String
        public let plain: String

        public init(subject: String, html: String, plain: String) {
            self.subject = subject
            self.html = html
            self.plain = plain
        }
    }

    // MARK: - Public API

    /// Renders the template by substituting all `{var_name}` tokens.
    /// - Parameters:
    ///   - template: The `EmailTemplate` to render.
    ///   - context: A dictionary mapping var names (without braces) to values.
    ///              Keys present in the template but absent from the context are left as-is.
    /// - Returns: A `Rendered` struct with substituted subject, html, and plain bodies.
    public static func render(template: EmailTemplate, context: [String: String]) -> Rendered {
        let subject = substitute(template.subject, context: context)
        let html = substitute(template.htmlBody, context: context)
        let plain: String
        if let explicit = template.plainBody, !explicit.isEmpty {
            plain = substitute(explicit, context: context)
        } else {
            plain = stripHTML(from: html)
        }
        return Rendered(subject: subject, html: html, plain: plain)
    }

    // MARK: - Private helpers

    /// Replaces all `{key}` occurrences using the context dictionary.
    private static func substitute(_ text: String, context: [String: String]) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for (key, value) in context {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// Removes all HTML tags from `html` and decodes common HTML entities.
    static func stripHTML(from html: String) -> String {
        guard !html.isEmpty else { return html }

        // Use NSAttributedString for entity decoding + tag stripping (main thread safe in tests).
        // Fall back to regex-only approach if attributed string init fails.
        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
           ) {
            return attributed.string
        }

        // Fallback: regex-strip tags + decode common entities manually.
        return decodeEntities(regexStripTags(from: html))
    }

    private static func regexStripTags(from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
