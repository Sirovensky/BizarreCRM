import Foundation

// MARK: - Step4Validator  (Timezone + Currency + Locale)
// All three fields are required. Device defaults satisfy this automatically.

public enum Step4Validator {

    /// Additional well-known timezone identifiers not always present in `knownTimeZoneIdentifiers`.
    static let extraValidTimezones: Set<String> = ["UTC", "GMT", "Etc/UTC", "Etc/GMT"]

    public static func validateTimezone(_ tz: String) -> ValidationResult {
        let trimmed = tz.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Timezone is required.")
        }
        let isKnown = TimeZone.knownTimeZoneIdentifiers.contains(trimmed)
            || extraValidTimezones.contains(trimmed)
            || TimeZone(identifier: trimmed) != nil
        guard isKnown else {
            return .invalid("Unknown timezone identifier.")
        }
        return .valid
    }

    public static func validateCurrency(_ currency: String) -> ValidationResult {
        let trimmed = currency.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Currency is required.")
        }
        // Accept the MVP shortlist plus any valid ISO 4217 code (3 uppercase letters)
        guard trimmed.count == 3, trimmed == trimmed.uppercased() else {
            return .invalid("Enter a valid 3-letter currency code (e.g. USD).")
        }
        return .valid
    }

    public static func validateLocale(_ locale: String) -> ValidationResult {
        let trimmed = locale.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Locale is required.")
        }
        return .valid
    }

    public static func isNextEnabled(timezone: String, currency: String, locale: String) -> Bool {
        validateTimezone(timezone).isValid &&
        validateCurrency(currency).isValid &&
        validateLocale(locale).isValid
    }
}
