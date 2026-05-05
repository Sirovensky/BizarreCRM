import Foundation

// §28.7 Logging redaction — Sensitive-field marker property wrapper
//
// This property wrapper serves two purposes:
//   1. Documents at the declaration site that the stored value is PII /
//      sensitive (replaces ad-hoc comments like "// don't log this").
//   2. Provides a `redacted` projection that returns the value scrubbed via
//      `SensitiveFieldRedactor`, preventing accidental PII leakage into logs,
//      crash reporters, or debug descriptions.
//
// ## Design constraints
// - The wrapper stores the original value unchanged. Encryption / Keychain
//   storage is a separate concern handled by `KeychainStore`.
// - The `wrappedValue` gives full access (for actual use in the domain);
//   only `projectedValue` (the `$field` syntax) ever returns redacted output.
// - This is a marker + convenience, NOT a security boundary. Do not rely on it
//   to prevent access by a determined attacker — it only guards log call sites.

// MARK: - SensitiveField

/// Property wrapper that marks a stored value as PII / security-sensitive and
/// provides an always-redacted projection for safe logging.
///
/// ## Usage
/// ```swift
/// struct CustomerRecord {
///     @SensitiveField(.email, .phone) var contactInfo: String
///
///     func logForAudit() {
///         // Safe: $contactInfo is the SensitiveFieldProjection
///         AppLog.privacy.debug("Contact: \($contactInfo.redacted, privacy: .public)")
///     }
/// }
/// ```
///
/// Access the raw value via `contactInfo`; access the redacted string via
/// `$contactInfo.redacted`.
@propertyWrapper
public struct SensitiveField<Value: Sendable>: Sendable {

    // MARK: - Storage

    public var wrappedValue: Value

    /// The PII categories this field belongs to, used to select redaction rules.
    public let categories: [DataHandlingCategory]

    // MARK: - Init

    /// - Parameters:
    ///   - wrappedValue: The initial value of the property.
    ///   - categories:   One or more ``DataHandlingCategory`` values that
    ///                   describe what kind of PII the field holds. Used by the
    ///                   `projectedValue` to choose which regex rules to apply.
    public init(wrappedValue: Value, _ categories: DataHandlingCategory...) {
        self.wrappedValue = wrappedValue
        self.categories   = categories.isEmpty ? DataHandlingCategory.allCases : categories
    }

    /// Convenience init accepting an array (useful when building dynamic category
    /// lists that aren't known at the call site).
    public init(wrappedValue: Value, categories: [DataHandlingCategory]) {
        self.wrappedValue = wrappedValue
        self.categories   = categories.isEmpty ? DataHandlingCategory.allCases : categories
    }

    // MARK: - Projected value

    /// `$field` gives a ``SensitiveFieldProjection`` whose `.redacted` property
    /// produces a redacted string safe to pass to logging APIs.
    public var projectedValue: SensitiveFieldProjection<Value> {
        SensitiveFieldProjection(value: wrappedValue, categories: categories)
    }
}

// MARK: - SensitiveFieldProjection

/// The projected value type for ``SensitiveField``.
///
/// Access via the `$` prefix on the property name.
public struct SensitiveFieldProjection<Value: Sendable>: Sendable {

    private let value: Value
    private let categories: [DataHandlingCategory]

    init(value: Value, categories: [DataHandlingCategory]) {
        self.value      = value
        self.categories = categories
    }

    // MARK: - Redacted accessor

    /// Returns `value` passed through ``SensitiveFieldRedactor`` using the
    /// declared categories.
    ///
    /// If `Value` is not `String`-convertible the redactor falls back to a
    /// generic `<redacted>` token.
    public var redacted: String {
        if let string = value as? String {
            return SensitiveFieldRedactor.redact(string, categories: categories)
        }
        // Non-string types: return a category-aware placeholder.
        let label = categories.map(\.displayName).joined(separator: "/")
        return "<redacted:\(label)>"
    }

    /// Raw value, unchanged. Prefer `wrappedValue` on the property wrapper
    /// for clarity; this accessor is provided for completeness.
    public var raw: Value { value }
}

// MARK: - CustomStringConvertible / CustomDebugStringConvertible guards

/// Ensure that interpolating a `SensitiveField` directly (not via the `$`
/// projection) produces an explicit warning string rather than leaking the
/// raw value.
///
/// The string deliberately includes "SENSITIVE" so log-scraper rules can
/// catch accidental raw interpolation in CI.
extension SensitiveField: CustomStringConvertible {
    public var description: String {
        "SensitiveField<SENSITIVE — use $field.redacted for logging>"
    }
}

extension SensitiveField: CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }
}
