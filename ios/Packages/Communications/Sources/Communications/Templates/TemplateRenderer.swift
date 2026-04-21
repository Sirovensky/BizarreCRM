import Foundation

// MARK: - TemplateRenderer

/// Pure, stateless helper for dynamic-variable substitution in message templates.
/// Supported variables: `{first_name}`, `{last_name}`, `{ticket_no}`,
/// `{company}`, `{amount}`, `{date}`.
///
/// Pass `nil` for any variable to leave it as-is (useful for preview).
public enum TemplateRenderer: Sendable {

    // MARK: - Public interface

    public struct Variables: Sendable {
        public var firstName: String?
        public var lastName: String?
        public var ticketNo: String?
        public var company: String?
        public var amount: String?
        public var date: String?

        public static let sample = Variables(
            firstName: "Jane",
            lastName: "Smith",
            ticketNo: "TKT-0042",
            company: "Acme Corp",
            amount: "$149.99",
            date: DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        )

        public init(
            firstName: String? = nil,
            lastName: String? = nil,
            ticketNo: String? = nil,
            company: String? = nil,
            amount: String? = nil,
            date: String? = nil
        ) {
            self.firstName = firstName
            self.lastName = lastName
            self.ticketNo = ticketNo
            self.company = company
            self.amount = amount
            self.date = date
        }
    }

    /// Renders `body` by substituting all known `{var}` placeholders.
    /// Unknown placeholders are left unchanged.
    public static func render(_ body: String, variables: Variables) -> String {
        var result = body
        let replacements: [(String, String?)] = [
            ("{first_name}", variables.firstName),
            ("{last_name}", variables.lastName),
            ("{ticket_no}", variables.ticketNo),
            ("{company}", variables.company),
            ("{amount}", variables.amount),
            ("{date}", variables.date),
        ]
        for (key, value) in replacements {
            guard let v = value else { continue }
            result = result.replacingOccurrences(of: key, with: v)
        }
        return result
    }

    /// Returns all `{var}` tokens found in `body`.
    public static func extractVariables(from body: String) -> [String] {
        let pattern = "\\{[a-zA-Z_]+\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).compactMap {
            Range($0.range, in: body).map { String(body[$0]) }
        }
    }
}
