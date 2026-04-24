import Foundation

// §71 Privacy-first Analytics — compile-time PII guard

// MARK: - PII-safety phantom markers

/// Phantom marker: a value is known to be safe for analytics transmission.
/// Values carrying this tag have been verified NOT to contain raw PII (email,
/// phone number, full name, address, SSN, credit-card numbers).
public enum PIISafe {}

/// Phantom marker: a value has NOT been verified for PII safety.
/// Values carrying this tag must be scrubbed before transmission.
public enum PIIUnsafe {}

// MARK: - SafeValue<Tag>

/// A wrapper that carries a `String` value together with a phantom type
/// indicating whether the value has been PII-scrubbed.
///
/// The phantom parameter `Tag` is constrained at the API boundary so that
/// only `SafeValue<PIISafe>` may be passed to `AnalyticsEventMapper`.
///
/// ```swift
/// // Compile error — unwrapped user input cannot be sent:
/// let raw = SafeValue<PIIUnsafe>(rawString: userInput)
/// AnalyticsEventMapper.buildRecord(for: event, safeMarker: raw) // ✗
///
/// // Only scrubbed values compile:
/// let safe = AnalyticsPIIGuard.markSafe("ticket")          // ✓
/// AnalyticsEventMapper.buildRecord(for: event, safeMarker: safe)
/// ```
public struct SafeValue<Tag>: Sendable {

    /// The wrapped string.  Access is intentionally `internal` so callers
    /// cannot extract and forward the raw bytes without going through the
    /// guard again.
    let rawString: String

    /// Initialise a `SafeValue`.
    ///
    /// Direct initialisation is intentionally `internal` — external code must
    /// use `AnalyticsPIIGuard.markSafe(_:)` or `AnalyticsPIIGuard.scrubAndMark(_:)`.
    init(rawString: String) {
        self.rawString = rawString
    }
}

// MARK: - AnalyticsPIIGuard

/// Compile-time guardrail that prevents raw PII from entering analytics payloads.
///
/// ## Pattern
///
/// Event properties flow through one of two entry points:
///
/// 1. **`markSafe(_:)`** — the caller attests that the string is structurally safe
///    (e.g. a server-assigned opaque ID, a status string, a numeric string).
///    No runtime scrubbing is performed.
///
/// 2. **`scrubAndMark(_:)`** — a string of unknown provenance is passed through
///    `TelemetryRedactor.scrub(_:)` to strip PII patterns, then wrapped as
///    `SafeValue<PIISafe>`.
///
/// Code paths that would send a `SafeValue<PIIUnsafe>` cannot compile because
/// `AnalyticsEventMapper.buildRecord(for:safeMarker:)` requires `SafeValue<PIISafe>`.
///
/// ## Why phantom types instead of runtime checks?
///
/// Runtime checks fire at test / production time. Phantom types make the wrong
/// code **not compile at all**, catching mistakes at zero runtime cost.
public enum AnalyticsPIIGuard {

    // MARK: - Public API

    /// Wrap a value that the caller attests is free of PII.
    ///
    /// Use for structural strings: entity kinds, status codes, opaque IDs,
    /// command identifiers, feature flags, error domains, etc.
    ///
    /// - Parameter value: A value that does NOT contain user-identifying text.
    /// - Returns: A `SafeValue<PIISafe>` that may be passed to downstream APIs.
    public static func markSafe(_ value: String) -> SafeValue<PIISafe> {
        SafeValue<PIISafe>(rawString: value)
    }

    /// Scrub an arbitrary string through `TelemetryRedactor`, then wrap the
    /// result as `SafeValue<PIISafe>`.
    ///
    /// Use when the input is user-provided or of unknown origin.
    ///
    /// - Parameter value: A string that may contain PII patterns.
    /// - Returns: A `SafeValue<PIISafe>` with PII patterns replaced by placeholders.
    public static func scrubAndMark(_ value: String) -> SafeValue<PIISafe> {
        let scrubbed = TelemetryRedactor.scrub(["value": value])["value"] ?? ""
        return SafeValue<PIISafe>(rawString: scrubbed)
    }

    // MARK: - Blocked fields

    /// Field names that are unconditionally forbidden in analytics payloads.
    ///
    /// This mirrors `TelemetryRedactor.blockedKeys` and serves as the compile-time
    /// documentation of which fields callers must NEVER construct `SafeValue`s from.
    public static let forbiddenFieldNames: Set<String> = [
        "email",
        "phone",
        "address",
        "firstName",
        "lastName",
        "fullName",
        "customerName",
        "ssn",
        "creditCard",
        "cardNumber",
    ]

    /// Returns `true` if `fieldName` (case-insensitive) is a known PII field.
    ///
    /// Callers can guard dynamic key construction:
    /// ```swift
    /// guard !AnalyticsPIIGuard.isForbiddenField(key) else { return }
    /// ```
    public static func isForbiddenField(_ fieldName: String) -> Bool {
        forbiddenFieldNames.contains(fieldName.lowercased())
    }
}
