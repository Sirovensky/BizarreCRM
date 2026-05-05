import Foundation
import Core

// §28 Security & Privacy — Receipt PII redactor
//
// Receipts that are shared via SMS, email, AirDrop, or printed may contain
// customer PII (phone, email) and payment-adjacent data (method label that
// may include last-4 digits). This helper redacts those fields for audit
// logging, analytics, and debug/crash reporting surfaces so the raw payload
// never leaks to non-customer destinations.
//
// Usage contract:
//   - `PosReceiptViewModel` uses `PosReceiptPIIRedactor.redactedForLog(_:)`
//     when writing send-status entries to `AppLog.pos` or telemetry.
//   - The *original* `PosReceiptPayload` is still used for the actual send
//     endpoints — this is a log/telemetry scrubber, not a payload mutator.

// MARK: - PosReceiptPIIRedactor

/// Stateless helper that produces a log-safe representation of a
/// ``PosReceiptPayload`` by redacting customer-identifying fields.
///
/// Fields redacted:
/// - `customerPhone` → `<phone>` (or absent)
/// - `customerEmail` → `<email>` (or absent)
/// - `methodLabel`  → last-4 digits replaced with `****` to scrub card-hint
///
/// All other fields (amounts, loyalty deltas, invoice ID) are non-PII and
/// preserved verbatim for diagnostic usefulness.
public enum PosReceiptPIIRedactor {

    // MARK: - Log-safe summary string

    /// Returns a log-safe single-line summary of `payload` suitable for
    /// `os_log` / `AppLog` calls. PII fields are replaced by tokens.
    ///
    /// Example output:
    /// ```
    /// Receipt(invoiceId=42, paid=1999¢, method="Cash", phone=<phone>, email=<absent>, loyalty=+5)
    /// ```
    public static func redactedSummary(for payload: PosReceiptPayload) -> String {
        let phone  = redactPhone(payload.customerPhone)
        let email  = redactEmail(payload.customerEmail)
        let method = redactMethodLabel(payload.methodLabel)
        let loyal  = payload.loyaltyDelta.map { "+\($0) pts" } ?? "none"

        return "Receipt(invoiceId=\(payload.invoiceId), " +
               "paid=\(payload.amountPaidCents)¢, " +
               "method=\"\(method)\", " +
               "phone=\(phone), " +
               "email=\(email), " +
               "loyalty=\(loyal))"
    }

    // MARK: - Field-level redactors (also public for composability)

    /// Replaces a phone string with `<phone>`, or returns `<absent>` when nil.
    public static func redactPhone(_ phone: String?) -> String {
        guard let phone, !phone.isEmpty else { return "<absent>" }
        return SensitiveFieldRedactor.redact(phone, categories: [.phone])
    }

    /// Replaces an email string with `<email>`, or returns `<absent>` when nil.
    public static func redactEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "<absent>" }
        return SensitiveFieldRedactor.redact(email, categories: [.email])
    }

    /// Scrubs trailing digit groups in a method label (e.g. "Visa •4242" → "Visa •****").
    ///
    /// Matches sequences of 3-4 trailing digits (card last-4 / last-3)
    /// preceded by a bullet, space, or dash separator. Generic labels like
    /// "Cash" or "Gift Card" are returned unchanged.
    public static func redactMethodLabel(_ label: String) -> String {
        // Pattern: optional separator (•·-space) followed by 3-4 digit cluster at end-of-string.
        // swiftlint:disable:next force_try
        let re = try! NSRegularExpression(pattern: #"([•·\- ])(\d{3,4})$"#)
        let range = NSRange(label.startIndex..., in: label)
        return re.stringByReplacingMatches(
            in: label,
            options: [],
            range: range,
            withTemplate: "$1****"
        )
    }
}
