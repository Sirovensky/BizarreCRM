import Foundation

// MARK: - LockoutState

/// Current lockout state for a single user's PIN attempts.
public enum LockoutState: Equatable, Sendable {
    /// No lockout — the user may attempt another PIN entry.
    case allowed
    /// Temporarily locked out until `until`.
    case locked(until: Date)
    /// Account revoked after too many failures — full re-authentication required.
    case revoked
}

// MARK: - LockoutRecord

/// Persisted per-user failure state.
public struct LockoutRecord: Codable, Sendable, Equatable {
    public let userId: Int
    public let failCount: Int
    public let lockUntil: Date?

    public init(userId: Int, failCount: Int, lockUntil: Date? = nil) {
        self.userId = userId
        self.failCount = failCount
        self.lockUntil = lockUntil
    }

    public static func zero(userId: Int) -> LockoutRecord {
        LockoutRecord(userId: userId, failCount: 0, lockUntil: nil)
    }
}

// MARK: - LockoutStorage protocol (testability seam)

public protocol LockoutStorage: Sendable {
    func load(userId: Int) -> LockoutRecord?
    func save(_ record: LockoutRecord) throws
    func delete(userId: Int) throws
}

// MARK: - InMemoryLockoutStorage (tests)

public final class InMemoryLockoutStorage: LockoutStorage, @unchecked Sendable {
    private var records: [Int: LockoutRecord] = [:]

    public init() {}

    public func load(userId: Int) -> LockoutRecord? { records[userId] }

    public func save(_ record: LockoutRecord) throws {
        records[record.userId] = record
    }

    public func delete(userId: Int) throws {
        records.removeValue(forKey: userId)
    }
}

// MARK: - UserDefaultsLockoutStorage (production)

/// Stores lockout records in UserDefaults (non-sensitive timing data).
/// Actual PIN hashes live in the Keychain via `MultiUserRoster`.
public struct UserDefaultsLockoutStorage: LockoutStorage, Sendable {
    private static let keyPrefix = "pin.lockout."
    private let suiteName: String?

    public init(suiteName: String? = "group.com.bizarrecrm") {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load(userId: Int) -> LockoutRecord? {
        let key = Self.keyPrefix + String(userId)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LockoutRecord.self, from: data)
    }

    public func save(_ record: LockoutRecord) throws {
        let key = Self.keyPrefix + String(record.userId)
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: key)
    }

    public func delete(userId: Int) throws {
        let key = Self.keyPrefix + String(userId)
        defaults.removeObject(forKey: key)
    }
}

// MARK: - PinLockoutPolicy actor

/// Manages escalating lockout for per-user PIN failures.
///
/// Lockout schedule (matching the server-side `pin_rate_limit` tiers):
///
/// | Cumulative failures | Lockout duration after the Nth failure |
/// | ------------------- | -------------------------------------- |
/// | 1 – 4               | none — try again immediately           |
/// | 5                   | 30 seconds                             |
/// | 6                   | 5 minutes                              |
/// | 7+                  | **revoked** — full re-auth required    |
///
/// State persists across app restarts so killing the app doesn't reset
/// the counter.
public actor PinLockoutPolicy {

    // MARK: - Constants

    /// Failures before first lockout tier (soft warning zone).
    public static let freeAttempts: Int = 4
    /// After this many cumulative failures the account is revoked.
    public static let maxFailures: Int = 7

    // MARK: - Shared instance

    public static let shared = PinLockoutPolicy()

    // MARK: - Storage

    private let storage: LockoutStorage

    // MARK: - Init

    public init(storage: LockoutStorage = UserDefaultsLockoutStorage()) {
        self.storage = storage
    }

    // MARK: - Public API

    /// Returns the current lockout state for `userId`.
    public func state(for userId: Int) -> LockoutState {
        guard let record = storage.load(userId: userId) else { return .allowed }
        return evaluate(record: record)
    }

    /// Records a failed attempt and returns the resulting lockout state.
    /// Call this after a PIN mismatch in `PinSwitchService`.
    public func recordFailure(userId: Int) throws -> LockoutState {
        let current = storage.load(userId: userId) ?? .zero(userId: userId)
        let newCount = current.failCount + 1

        let lockUntil: Date?
        if newCount >= Self.maxFailures {
            lockUntil = nil // revoked — no point storing a future date
        } else if let delay = Self.lockoutSeconds(for: newCount) {
            lockUntil = Date().addingTimeInterval(delay)
        } else {
            lockUntil = nil
        }

        let updated = LockoutRecord(userId: userId, failCount: newCount, lockUntil: lockUntil)
        try storage.save(updated)
        return evaluate(record: updated)
    }

    /// Clears the failure record for `userId` after a successful PIN match.
    public func recordSuccess(userId: Int) throws {
        try storage.delete(userId: userId)
    }

    /// Resets the record for `userId` (admin override / full re-auth).
    public func reset(userId: Int) throws {
        try storage.delete(userId: userId)
    }

    // MARK: - Internal helpers (internal so tests can assert)

    /// Maps a cumulative failure count to a lockout duration (or nil = no lockout yet).
    static func lockoutSeconds(for count: Int) -> TimeInterval? {
        switch count {
        case 5:       return 30            // 30 seconds
        case 6:       return 5 * 60        // 5 minutes
        default:      return nil
        }
    }

    // MARK: - Private

    private func evaluate(record: LockoutRecord) -> LockoutState {
        guard record.failCount > 0 else { return .allowed }
        if record.failCount >= Self.maxFailures { return .revoked }
        if let until = record.lockUntil, until > Date() { return .locked(until: until) }
        return .allowed
    }
}
