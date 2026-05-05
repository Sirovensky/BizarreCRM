import Foundation

// §34 Crisis Recovery helpers — EmergencyContactInfo
// Cached contact info (support phone, tenant admin) usable when network is down.

/// Immutable snapshot of emergency contact information.
///
/// Contains the support phone number and the tenant admin contact.
/// Stored entirely in `UserDefaults` so it remains readable when the network
/// (and therefore any remote config) is unavailable.
///
/// **No PII**: tenant admin is identified by a display name and a phone/email
/// string supplied by the tenant at setup — identical to what the tenant has
/// already chosen to expose to their own employees.
public struct EmergencyContactInfo: Codable, Sendable, Equatable {

    /// The support phone number (e.g. "+1-800-BIZARRE").
    public let supportPhone: String

    /// Tenant admin display name (no user ID, no account number).
    public let tenantAdminName: String

    /// Tenant admin contact string — phone or email, as configured by the tenant.
    public let tenantAdminContact: String

    public init(
        supportPhone: String,
        tenantAdminName: String,
        tenantAdminContact: String
    ) {
        self.supportPhone = supportPhone
        self.tenantAdminName = tenantAdminName
        self.tenantAdminContact = tenantAdminContact
    }
}

// MARK: — Cache

/// Persists and retrieves `EmergencyContactInfo` across cold starts.
///
/// Call `store(_:)` after a successful login or settings sync while the network is
/// available. Call `load()` during a crisis when network is unavailable.
public final class EmergencyContactCache: Sendable {

    // MARK: — Singleton

    public static let shared = EmergencyContactCache()

    // MARK: — Storage

    private let defaults: UserDefaults
    private static let cacheKey = "com.bizarrecrm.crisis.emergencyContact"

    // MARK: — Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: — Public API

    /// Persist emergency contacts to survive network outages.
    /// Returns the stored info unchanged (value semantics).
    @discardableResult
    public func store(_ info: EmergencyContactInfo) -> EmergencyContactInfo {
        guard let data = try? JSONEncoder().encode(info) else { return info }
        defaults.set(data, forKey: Self.cacheKey)
        return info
    }

    /// Load the last cached emergency contact info.
    /// Returns `nil` if nothing has been stored yet.
    public func load() -> EmergencyContactInfo? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(EmergencyContactInfo.self, from: data)
    }

    /// Remove the cached contact info (e.g. on logout).
    public func clear() {
        defaults.removeObject(forKey: Self.cacheKey)
    }
}
