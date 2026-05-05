import Foundation

// §79 Multi-Tenant Session management — roster actor

/// Thread-safe, Keychain-backed store for the full tenant roster.
///
/// Maintains an ordered list of `TenantSessionDescriptor` values
/// and exposes CRUD operations.  All mutations are isolated to the actor,
/// preventing concurrent roster corruption.
///
/// Persistence key layout:
///   account = "roster"  →  JSON-encoded `[TenantSessionDescriptor]`
public actor TenantSessionStore {

    // MARK: — Constants

    private static let rosterAccount = "roster"

    // MARK: — Dependencies

    private let keychain: any KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: — In-memory cache

    /// Lazily loaded on first access.
    private var cached: [TenantSessionDescriptor]?

    // MARK: — Init

    /// - Parameter keychain: Injectable Keychain store; defaults to production.
    public init(keychain: any KeychainStoring = TenantKeychainStore()) {
        self.keychain = keychain
        self.encoder = {
            let e = JSONEncoder()
            e.dateEncodingStrategy = .secondsSince1970
            return e
        }()
        self.decoder = {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .secondsSince1970
            return d
        }()
    }

    // MARK: — Public API

    /// Returns the full roster, sorted most-recently-used first.
    public func allTenants() throws -> [TenantSessionDescriptor] {
        if let cached { return cached }
        let loaded = try loadFromKeychain()
        cached = loaded
        return loaded
    }

    /// Returns the tenant with the given `id`, or `nil` if not present.
    public func tenant(id: String) throws -> TenantSessionDescriptor? {
        try allTenants().first { $0.id == id }
    }

    /// Upserts a descriptor into the roster.
    ///
    /// If a tenant with the same `id` already exists it is replaced (immutably)
    /// with the new value; otherwise the new descriptor is appended.
    public func upsert(_ descriptor: TenantSessionDescriptor) throws {
        var roster = try allTenants()
        if let idx = roster.firstIndex(where: { $0.id == descriptor.id }) {
            roster[idx] = descriptor
        } else {
            roster.append(descriptor)
        }
        try persist(roster)
    }

    /// Removes the tenant with the given `id` from the roster.
    /// A no-op if the tenant is not present.
    public func remove(id: String) throws {
        var roster = try allTenants()
        roster.removeAll { $0.id == id }
        try persist(roster)
    }

    /// Removes every tenant from the roster (e.g. on full sign-out).
    public func removeAll() throws {
        try persist([])
    }

    // MARK: — Private helpers

    private func loadFromKeychain() throws -> [TenantSessionDescriptor] {
        guard let data = try keychain.read(account: Self.rosterAccount) else {
            return []
        }
        do {
            let roster = try decoder.decode([TenantSessionDescriptor].self, from: data)
            return roster.sorted { $0.lastUsedAt > $1.lastUsedAt }
        } catch {
            throw KeychainError.decodingFailed
        }
    }

    private func persist(_ roster: [TenantSessionDescriptor]) throws {
        let data = try encoder.encode(roster)
        try keychain.write(data, account: Self.rosterAccount)
        cached = roster.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
}
