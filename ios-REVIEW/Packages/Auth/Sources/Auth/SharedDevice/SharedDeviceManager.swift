import Foundation

// MARK: - Storage abstraction (enables test injection)

/// Minimal key/value storage for SharedDeviceManager.
/// Backed by UserDefaults in production; an in-memory dict in tests.
public protocol SharedDeviceStorage: Sendable {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
}

/// Production implementation backed by a specific UserDefaults suite.
/// `UserDefaults` itself is not `Sendable`, so we wrap only the suite name
/// and re-create the instance on each access (cheap; UserDefaults caches internally).
public struct UserDefaultsDeviceStorage: SharedDeviceStorage, Sendable {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// In-memory storage for unit tests.
public final class InMemoryDeviceStorage: SharedDeviceStorage, @unchecked Sendable {
    private var store: [String: Bool] = [:]

    public init() {}

    public func bool(forKey key: String) -> Bool { store[key] ?? false }
    public func set(_ value: Bool, forKey key: String) { store[key] = value }
}

// MARK: - SharedDeviceManager

/// §2 Shared-device mode — manages state for iPads pinned to a counter.
///
/// When enabled:
/// - Session idle timeout shrinks from 15 min to 4 min (`SessionTimer` integration hook).
/// - Auth token expiry is server-returned; client defaults to 4 hours.
/// - Sign-out + PIN re-entry required on every new user.
///
/// Integration hook — wire into `SessionTimer` at session start:
/// ```swift
/// let timeout = await SharedDeviceManager.shared.isSharedDevice
///     ? SharedDeviceManager.sharedDeviceIdleTimeout
///     : SharedDeviceManager.normalIdleTimeout
/// let timer = SessionTimer(idleTimeout: timeout, onExpire: { await signOut() })
/// ```
public actor SharedDeviceManager {

    // MARK: - Constants

    /// Default max session length in shared-device mode: 4 hours.
    public static let defaultSessionDuration: TimeInterval = 4 * 60 * 60

    /// Idle timeout when shared-device mode is active: 4 minutes.
    public static let sharedDeviceIdleTimeout: TimeInterval = 4 * 60

    /// Normal idle timeout for reference: 15 minutes.
    public static let normalIdleTimeout: TimeInterval = 15 * 60

    // MARK: - Persistence key

    private static let key = "shared_device_mode"

    // MARK: - Shared instance

    public static let shared = SharedDeviceManager()

    // MARK: - State

    /// Whether shared-device mode is currently active.
    public private(set) var isSharedDevice: Bool

    /// When set, overrides the default 4-hour session cap.
    /// Typically provided by a tenant-admin API response.
    public private(set) var sessionExpiresAt: Date?

    private let storage: SharedDeviceStorage

    // MARK: - Init

    public init(storage: SharedDeviceStorage = UserDefaultsDeviceStorage()) {
        self.storage = storage
        self.isSharedDevice = storage.bool(forKey: SharedDeviceManager.key)
    }

    // MARK: - Public API

    /// Enable shared-device mode. Persists immediately.
    public func enable() {
        isSharedDevice = true
        storage.set(true, forKey: SharedDeviceManager.key)
    }

    /// Disable shared-device mode. Clears persisted flag and session expiry.
    public func disable() {
        isSharedDevice = false
        sessionExpiresAt = nil
        storage.set(false, forKey: SharedDeviceManager.key)
    }

    /// Override session expiry with a server-provided date.
    public func setSessionExpiry(_ date: Date?) {
        sessionExpiresAt = date
    }

    /// The effective session expiry date for the current session.
    public func effectiveSessionExpiry() -> Date? {
        guard isSharedDevice else { return nil }
        return sessionExpiresAt ?? Date(timeIntervalSinceNow: SharedDeviceManager.defaultSessionDuration)
    }

    /// The idle timeout to use when constructing `SessionTimer`.
    public func idleTimeout() -> TimeInterval {
        isSharedDevice ? SharedDeviceManager.sharedDeviceIdleTimeout : SharedDeviceManager.normalIdleTimeout
    }
}
