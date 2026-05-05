import Foundation

// MARK: - Step9Validator  (Invite Teammates)
// Emails must be valid RFC-5322 format; duplicates are rejected. Zero invitees is OK.

public enum Step9Validator {

    public static func validateEmail(_ email: String) -> ValidationResult {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Email address must not be empty.")
        }
        // Minimal RFC-5322-ish check: local@domain.tld
        let atParts = trimmed.components(separatedBy: "@")
        guard atParts.count == 2,
              !atParts[0].isEmpty,
              atParts[1].contains("."),
              let lastDot = atParts[1].lastIndex(of: "."),
              atParts[1].distance(from: lastDot, to: atParts[1].endIndex) > 2
        else {
            return .invalid("\"\(trimmed)\" is not a valid email address.")
        }
        return .valid
    }

    /// Parses a comma- or newline-separated list of emails.
    /// Returns (.valid, deduped array) or (.invalid, error) on first bad/duplicate entry.
    public static func validateEmailList(_ raw: String) -> (ValidationResult, [String]) {
        let separators = CharacterSet(charactersIn: ",\n")
        let candidates = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var deduped: [String] = []
        for email in candidates {
            let lower = email.lowercased()
            if seen.contains(lower) {
                return (.invalid("Duplicate email: \(email)."), [])
            }
            let r = validateEmail(email)
            guard r.isValid else { return (r, []) }
            seen.insert(lower)
            deduped.append(email)
        }
        return (.valid, deduped)
    }

    /// Wizard Next is enabled even with zero invitees (step is skippable).
    public static func isNextEnabled(raw: String) -> Bool {
        let (result, _) = validateEmailList(raw)
        return result.isValid
    }
}
