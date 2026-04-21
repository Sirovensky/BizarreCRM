import Foundation

// MARK: - ElevationSession

/// Manages a temporary permission elevation granted via manager PIN.
/// Elevation persists in-memory for 5 minutes (§47.8).
/// Thread-safe via actor isolation.
public actor ElevationSession {

    // MARK: Types

    public struct Grant: Sendable {
        /// The capability scope granted by elevation.
        public let scope: String
        /// Absolute deadline after which elevation expires.
        public let expiresAt: Date

        public var isValid: Bool {
            Date.now < expiresAt
        }
    }

    // MARK: Shared instance (DI overridable in tests)

    public static let shared = ElevationSession()

    // MARK: State

    private var grants: [String: Grant] = [:]
    private let sessionDuration: TimeInterval

    // MARK: Init

    public init(sessionDuration: TimeInterval = 5 * 60) {
        self.sessionDuration = sessionDuration
    }

    // MARK: API

    /// Grants elevation for the given scope for `sessionDuration` seconds.
    public func elevate(scope: String) {
        let grant = Grant(scope: scope, expiresAt: Date.now.addingTimeInterval(sessionDuration))
        grants[scope] = grant
    }

    /// Returns `true` if an active elevation exists for the given scope.
    public func isElevated(for scope: String) -> Bool {
        guard let grant = grants[scope] else { return false }
        if grant.isValid { return true }
        grants.removeValue(forKey: scope)   // prune expired
        return false
    }

    /// Revokes a specific elevation scope immediately.
    public func revoke(scope: String) {
        grants.removeValue(forKey: scope)
    }

    /// Revokes all active elevations.
    public func revokeAll() {
        grants.removeAll()
    }

    /// Remaining seconds for the named scope's grant, or nil if not elevated.
    public func remainingSeconds(for scope: String) -> TimeInterval? {
        guard let grant = grants[scope], grant.isValid else { return nil }
        return grant.expiresAt.timeIntervalSinceNow
    }

    /// Prunes all expired grants (call periodically to keep memory tidy).
    public func pruneExpired() {
        grants = grants.filter { $0.value.isValid }
    }
}
