import Foundation

// §28 Security & Privacy helpers — Privacy Manifest data layer

// MARK: - PrivacyAccessedAPIReason

/// Reason codes for a single NSPrivacyAccessedAPIType entry.
///
/// Each ``PrivacyAPIEntry`` carries one or more reason codes that explain why
/// the app uses a particular system API.  The raw string values must match the
/// Apple-documented reason-code strings exactly.
public struct PrivacyAPIReasonCode: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Predefined reason codes

public extension PrivacyAPIReasonCode {

    // NSUserDefaults
    /// Accessing user defaults for app functionality (not for fingerprinting).
    static let userDefaultsCA92 = PrivacyAPIReasonCode(rawValue: "CA92.1")
    /// Accessing user defaults to read data written by app-group extensions.
    static let userDefaults1C8F = PrivacyAPIReasonCode(rawValue: "1C8F.1")

    // FileTimestamp
    /// File access required to verify file integrity, not to fingerprint the device.
    static let fileTimestampC617 = PrivacyAPIReasonCode(rawValue: "C617.1")
    /// Display file modification times in the UI.
    static let fileTimestamp3B52 = PrivacyAPIReasonCode(rawValue: "3B52.1")

    // SystemBootTime
    /// Used for calculating uptime to measure app performance on device.
    static let systemBootTime35F9 = PrivacyAPIReasonCode(rawValue: "35F9.1")

    // DiskSpace
    /// Display remaining disk space to the user.
    static let diskSpace85F4 = PrivacyAPIReasonCode(rawValue: "85F4.1")
    /// Prevent writing large data when insufficient disk space exists.
    static let diskSpaceE174 = PrivacyAPIReasonCode(rawValue: "E174.1")
}

// MARK: - PrivacyAPIType

/// The NSPrivacyAccessedAPIType identifiers defined by Apple.
public enum PrivacyAPIType: String, Hashable, Sendable, CaseIterable, Codable {
    case userDefaults   = "NSPrivacyAccessedAPICategoryUserDefaults"
    case fileTimestamp  = "NSPrivacyAccessedAPICategoryFileTimestamp"
    case systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
    case diskSpace      = "NSPrivacyAccessedAPICategoryDiskSpace"
}

// MARK: - PrivacyAPIEntry

/// A single entry in the ``PrivacyManifest/accessedAPITypes`` list —
/// one ``PrivacyAPIType`` paired with the reason codes that justify its use.
public struct PrivacyAPIEntry: Hashable, Sendable, Codable {

    /// The category of system API being accessed.
    public let apiType: PrivacyAPIType

    /// One or more non-empty reason codes explaining why the API is used.
    public let reasons: [PrivacyAPIReasonCode]

    public init(apiType: PrivacyAPIType, reasons: [PrivacyAPIReasonCode]) {
        precondition(!reasons.isEmpty, "PrivacyAPIEntry must have at least one reason code")
        self.apiType = apiType
        self.reasons = reasons
    }
}

// MARK: - PrivacyManifest

/// Typed representation of the NSPrivacyAccessedAPITypes section of a
/// PrivacyInfo.xcprivacy file.
///
/// This is a **data-layer** struct — it describes what the app declares,
/// enabling tests to verify completeness and correct reason codes.
/// It does not read or write any plist file.
///
/// ## Usage
/// ```swift
/// let manifest = PrivacyManifest.bizarreCRM
/// for entry in manifest.accessedAPITypes {
///     print(entry.apiType.rawValue, entry.reasons.map(\.rawValue))
/// }
/// ```
public struct PrivacyManifest: Sendable {

    // MARK: - Properties

    /// All API-category entries declared by this app.
    public let accessedAPITypes: [PrivacyAPIEntry]

    // MARK: - Init

    public init(accessedAPITypes: [PrivacyAPIEntry]) {
        self.accessedAPITypes = accessedAPITypes
    }

    // MARK: - Lookup helpers

    /// Returns the entry for a given API type, or `nil` if not declared.
    public func entry(for type: PrivacyAPIType) -> PrivacyAPIEntry? {
        accessedAPITypes.first { $0.apiType == type }
    }

    /// Returns `true` when every ``PrivacyAPIType`` case has an entry with at
    /// least one reason code.
    public var coversAllRequiredTypes: Bool {
        let declaredTypes = Set(accessedAPITypes.map(\.apiType))
        return PrivacyAPIType.allCases.allSatisfy { declaredTypes.contains($0) }
    }
}

// MARK: - App manifest

public extension PrivacyManifest {

    /// The canonical BizarreCRM privacy manifest.
    ///
    /// Keep this in sync with `App/Resources/PrivacyInfo.xcprivacy`.
    static let bizarreCRM = PrivacyManifest(accessedAPITypes: [
        PrivacyAPIEntry(
            apiType: .userDefaults,
            reasons: [.userDefaultsCA92, .userDefaults1C8F]
        ),
        PrivacyAPIEntry(
            apiType: .fileTimestamp,
            reasons: [.fileTimestampC617, .fileTimestamp3B52]
        ),
        PrivacyAPIEntry(
            apiType: .systemBootTime,
            reasons: [.systemBootTime35F9]
        ),
        PrivacyAPIEntry(
            apiType: .diskSpace,
            reasons: [.diskSpace85F4, .diskSpaceE174]
        ),
    ])
}
