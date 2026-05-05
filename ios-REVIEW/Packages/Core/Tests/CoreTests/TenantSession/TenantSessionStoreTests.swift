import XCTest
@testable import Core

// §79 Multi-Tenant Session management — store persistence tests

// MARK: — In-memory Keychain fake

/// Thread-safe in-memory replacement for the real Keychain.
/// Each test instance is independent.
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {

    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func read(account: String) throws -> Data? {
        lock.withLock { storage[account] }
    }

    func write(_ data: Data, account: String) throws {
        lock.withLock { storage[account] = data }
    }

    func delete(account: String) throws {
        lock.withLock { storage.removeValue(forKey: account) }
    }
}

// MARK: — Helpers

private func makeStore(keychain: InMemoryKeychainStore = InMemoryKeychainStore()) -> TenantSessionStore {
    TenantSessionStore(keychain: keychain)
}

private func descriptor(
    id: String,
    name: String = "Tenant",
    url: String = "https://tenant.example.com",
    lastUsedAt: Date = Date()
) -> TenantSessionDescriptor {
    TenantSessionDescriptor(
        id: id,
        displayName: name,
        baseURL: URL(string: url)!,
        lastUsedAt: lastUsedAt
    )
}

// MARK: — Tests

final class TenantSessionStoreTests: XCTestCase {

    // MARK: — Empty store

    func test_allTenants_returnsEmpty_onFreshStore() async throws {
        let store = makeStore()
        let tenants = try await store.allTenants()
        XCTAssertTrue(tenants.isEmpty)
    }

    // MARK: — Upsert (insert)

    func test_upsert_addsNewTenant() async throws {
        let store = makeStore()
        let t = descriptor(id: "acme")
        try await store.upsert(t)

        let tenants = try await store.allTenants()
        XCTAssertEqual(tenants.count, 1)
        XCTAssertEqual(tenants.first?.id, "acme")
    }

    func test_upsert_multipleTenants_allStored() async throws {
        let store = makeStore()
        try await store.upsert(descriptor(id: "alpha"))
        try await store.upsert(descriptor(id: "beta"))
        try await store.upsert(descriptor(id: "gamma"))

        let tenants = try await store.allTenants()
        XCTAssertEqual(tenants.count, 3)
    }

    // MARK: — Upsert (replace / immutable update)

    func test_upsert_replacesExistingTenant_byId() async throws {
        let store = makeStore()
        try await store.upsert(descriptor(id: "acme", name: "Old Name"))
        try await store.upsert(descriptor(id: "acme", name: "New Name"))

        let tenants = try await store.allTenants()
        XCTAssertEqual(tenants.count, 1, "upsert must not duplicate")
        XCTAssertEqual(tenants.first?.displayName, "New Name")
    }

    // MARK: — tenant(id:)

    func test_tenantById_returnsCorrectDescriptor() async throws {
        let store = makeStore()
        try await store.upsert(descriptor(id: "a"))
        try await store.upsert(descriptor(id: "b"))

        let found = try await store.tenant(id: "b")
        XCTAssertEqual(found?.id, "b")
    }

    func test_tenantById_returnsNil_whenMissing() async throws {
        let store = makeStore()
        let found = try await store.tenant(id: "nonexistent")
        XCTAssertNil(found)
    }

    // MARK: — Remove

    func test_remove_deletesSpecifiedTenant() async throws {
        let store = makeStore()
        try await store.upsert(descriptor(id: "keep"))
        try await store.upsert(descriptor(id: "delete-me"))

        try await store.remove(id: "delete-me")

        let tenants = try await store.allTenants()
        XCTAssertEqual(tenants.count, 1)
        XCTAssertEqual(tenants.first?.id, "keep")
    }

    func test_remove_nonExistent_doesNotThrow() async throws {
        let store = makeStore()
        try await store.remove(id: "ghost")
        let tenants = try await store.allTenants()
        XCTAssertTrue(tenants.isEmpty)
    }

    // MARK: — RemoveAll

    func test_removeAll_emptiesRoster() async throws {
        let store = makeStore()
        try await store.upsert(descriptor(id: "a"))
        try await store.upsert(descriptor(id: "b"))

        try await store.removeAll()

        let tenants = try await store.allTenants()
        XCTAssertTrue(tenants.isEmpty)
    }

    // MARK: — Sorting (most-recent first)

    func test_allTenants_sortedMostRecentFirst() async throws {
        let store = makeStore()
        let older = descriptor(id: "old", lastUsedAt: Date(timeIntervalSinceNow: -3600))
        let newer = descriptor(id: "new", lastUsedAt: Date(timeIntervalSinceNow: -10))

        // Insert in oldest-first order; result must flip.
        try await store.upsert(older)
        try await store.upsert(newer)

        let tenants = try await store.allTenants()
        XCTAssertEqual(tenants.first?.id, "new", "most-recently-used must appear first")
    }

    // MARK: — Persistence (Keychain round-trip)

    func test_persistsAcrossStoreInstances() async throws {
        let keychain = InMemoryKeychainStore()
        let storeA = makeStore(keychain: keychain)
        try await storeA.upsert(descriptor(id: "persist-me", name: "Acme Corp"))

        // Create a second store backed by the same keychain.
        let storeB = TenantSessionStore(keychain: keychain)
        let tenants = try await storeB.allTenants()

        XCTAssertEqual(tenants.count, 1)
        XCTAssertEqual(tenants.first?.displayName, "Acme Corp")
    }

    func test_removeAll_persistsAcrossInstances() async throws {
        let keychain = InMemoryKeychainStore()
        let storeA = makeStore(keychain: keychain)
        try await storeA.upsert(descriptor(id: "x"))
        try await storeA.removeAll()

        let storeB = TenantSessionStore(keychain: keychain)
        let tenants = try await storeB.allTenants()
        XCTAssertTrue(tenants.isEmpty)
    }

    // MARK: — Descriptor immutability

    func test_touchingLastUsed_doesNotMutateOriginal() {
        let original = descriptor(id: "a", lastUsedAt: Date(timeIntervalSinceReferenceDate: 0))
        let touched = original.touchingLastUsed(at: Date(timeIntervalSinceReferenceDate: 1000))

        XCTAssertEqual(original.lastUsedAt, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(touched.lastUsedAt,  Date(timeIntervalSinceReferenceDate: 1000))
        XCTAssertEqual(original.id, touched.id)
    }
}
