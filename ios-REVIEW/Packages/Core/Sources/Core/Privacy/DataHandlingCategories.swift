import Foundation

// §28 Security & Privacy helpers — PII data-handling categories

// MARK: - SensitivityLevel

/// Indicates how sensitive a particular PII category is from a privacy
/// and regulatory perspective.
public enum SensitivityLevel: Int, Comparable, Sendable, Hashable, CaseIterable, Codable {

    /// Low sensitivity — aggregated or pseudonymous data.
    case low    = 1

    /// Medium sensitivity — identifiable but not immediately harmful if disclosed.
    case medium = 2

    /// High sensitivity — directly identifiable or financially sensitive.
    case high   = 3

    /// Critical sensitivity — regulated, financial, or uniquely identifying data
    /// whose exposure causes serious harm.
    case critical = 4

    public static func < (lhs: SensitivityLevel, rhs: SensitivityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DataHandlingCategory

/// Enumeration of PII categories handled by BizarreCRM.
///
/// Each case carries:
/// - A human-readable ``displayName``.
/// - A ``sensitivityLevel`` used by ``SensitiveFieldRedactor`` and UI to decide
///   how aggressively to redact or blur values.
///
/// ## Usage
/// ```swift
/// let category = DataHandlingCategory.paymentCard
/// print(category.sensitivityLevel) // .critical
/// ```
public enum DataHandlingCategory: String, Hashable, Sendable, CaseIterable, Codable {

    /// Email address (e.g. `alice@example.com`).
    case email

    /// Phone number in any regional format.
    case phone

    /// Personal name — first, last, or full.
    case name

    /// Physical or mailing address.
    case address

    /// Payment card number (PAN), CVV, or expiry.
    case paymentCard

    /// A hardware or advertising device identifier (IDFA, IDFV, serial number).
    case deviceID

    /// Coarse geographic location (city, region, or ~1 km radius).
    case locationCoarse

    // MARK: - Derived properties

    /// Human-readable label suitable for privacy disclosures.
    public var displayName: String {
        switch self {
        case .email:         return "Email Address"
        case .phone:         return "Phone Number"
        case .name:          return "Personal Name"
        case .address:       return "Physical Address"
        case .paymentCard:   return "Payment Card"
        case .deviceID:      return "Device Identifier"
        case .locationCoarse: return "Coarse Location"
        }
    }

    /// Risk level that determines redaction and display policy.
    public var sensitivityLevel: SensitivityLevel {
        switch self {
        case .locationCoarse: return .low
        case .deviceID:       return .medium
        case .name:           return .medium
        case .email:          return .high
        case .phone:          return .high
        case .address:        return .high
        case .paymentCard:    return .critical
        }
    }

    /// Returns `true` when the category is regulated under PCI-DSS or similar
    /// financial-data standards.
    public var isFinancialData: Bool {
        self == .paymentCard
    }

    /// Returns `true` when the category is typically regulated under GDPR / CCPA
    /// as "special category" or directly identifiable personal data.
    public var requiresExplicitConsent: Bool {
        switch self {
        case .email, .phone, .name, .address, .paymentCard:
            return true
        case .deviceID, .locationCoarse:
            return false
        }
    }
}
