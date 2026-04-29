import Foundation

/// Display and normalization helpers for North American phone numbers.
///
/// BizarreCRM standardizes on two phone representations:
/// - **Display**: `+1 (XXX)-XXX-XXXX` — shown in customer cards, SMS headers,
///   and ticket detail views.
/// - **Normalized (E.164)**: `+1XXXXXXXXXX` — stored in the database, used in
///   API payloads and SMS sends.
///
/// Both functions are pure (no side-effects) and safe to call from any actor.
///
/// ## Example
/// ```swift
/// PhoneFormatter.format("5551234567")     // "+1 (555)-123-4567"
/// PhoneFormatter.normalize("(555) 123-4567") // "+15551234567"
/// ```
///
/// ## See Also
/// - ``PhoneValidator`` for validating input before formatting.
public enum PhoneFormatter {
    /// Format a raw phone string for display as `+1 (XXX)-XXX-XXXX`.
    ///
    /// Strips all non-digit characters, handles 10-digit NANP and 11-digit
    /// `1XXXXXXXXXX` inputs.  Returns `raw` unchanged when the digit count does
    /// not match a recognized pattern.
    ///
    /// - Parameter raw: Any phone string — formatted, E.164, or bare digits.
    /// - Returns: A display-ready string such as `"+1 (555)-123-4567"`, or
    ///   `raw` if the number of digits is unrecognized.
    public static func format(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let trimmed: String
        if digits.count == 11, digits.hasPrefix("1") {
            trimmed = String(digits.dropFirst())
        } else {
            trimmed = digits
        }
        guard trimmed.count == 10 else { return raw }
        let area = trimmed.prefix(3)
        let mid = trimmed.dropFirst(3).prefix(3)
        let last = trimmed.suffix(4)
        return "+1 (\(area))-\(mid)-\(last)"
    }

    /// Normalize a phone string to E.164 format (`+1XXXXXXXXXX`).
    ///
    /// Accepts 10-digit NANP bare digits or 11-digit strings starting with `1`.
    /// Returns `raw` unchanged when the digit count is unrecognized, so callers
    /// can pass the result directly to ``PhoneValidator`` to detect failures.
    ///
    /// - Parameter raw: Any phone string.
    /// - Returns: E.164 string (e.g. `"+15551234567"`) or `raw` on mismatch.
    public static func normalize(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return raw
    }
}
