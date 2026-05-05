import XCTest
@testable import Core

// MARK: - §31.3 Integration tests — Keychain
//
// Real Keychain integration test (no fakes). Uses an isolated test
// service name so production Keychain entries are never touched, and
// performs aggressive cleanup in `setUp` + `tearDown` so the suite
// stays hermetic across runs.
//
// These tests purposely target `TenantKeychainStore` (the production
// `KeychainStoring` adopter) so we exercise the real Security-framework
// `SecItemAdd` / `SecItemUpdate` / `SecItemCopyMatching` / `SecItemDelete`
// code paths.
final class KeychainIntegrationTests: XCTestCase {

    private let service = "com.bizarrecrm.tests.keychain.\(UUID().uuidString)"
    private var store: TenantKeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = TenantKeychainStore(service: service)
        // Defensive cleanup — should be a no-op for a freshly-minted service,
        // but guards against test-runner reuse of the same simulator keychain.
        try? store.delete(account: "alpha")
        try? store.delete(account: "beta")
    }

    override func tearDownWithError() throws {
        try? store.delete(account: "alpha")
        try? store.delete(account: "beta")
        store = nil
        try super.tearDownWithError()
    }

    // MARK: - Read after write

    func test_write_thenRead_returnsSameBytes() throws {
        let payload = Data("hello-keychain".utf8)
        try store.write(payload, account: "alpha")
        let readBack = try store.read(account: "alpha")
        XCTAssertEqual(readBack, payload)
    }

    // MARK: - Update overwrites previous value

    func test_write_twice_returnsLatestValue() throws {
        try store.write(Data("v1".utf8), account: "alpha")
        try store.write(Data("v2".utf8), account: "alpha")
        let readBack = try store.read(account: "alpha")
        XCTAssertEqual(readBack, Data("v2".utf8))
    }

    // MARK: - Read-missing returns nil (NOT a thrown error)

    func test_read_missingAccount_returnsNil() throws {
        let readBack = try store.read(account: "never-written")
        XCTAssertNil(readBack)
    }

    // MARK: - Delete is idempotent

    func test_delete_thenRead_returnsNil() throws {
        try store.write(Data("ephemeral".utf8), account: "alpha")
        try store.delete(account: "alpha")
        XCTAssertNil(try store.read(account: "alpha"))
    }

    func test_delete_missingAccount_doesNotThrow() {
        // SecItemDelete returns errSecItemNotFound for missing items — the
        // store treats that as success.
        XCTAssertNoThrow(try store.delete(account: "never-written"))
    }

    // MARK: - Account isolation

    func test_writes_areIsolatedPerAccount() throws {
        try store.write(Data("aaa".utf8), account: "alpha")
        try store.write(Data("bbb".utf8), account: "beta")
        XCTAssertEqual(try store.read(account: "alpha"), Data("aaa".utf8))
        XCTAssertEqual(try store.read(account: "beta"),  Data("bbb".utf8))
    }

    // MARK: - Service isolation

    func test_writes_areIsolatedPerService() throws {
        // A second store with a different service must not see the first
        // store's entries — proves we won't collide with production keys.
        let otherService = "com.bizarrecrm.tests.keychain.other.\(UUID().uuidString)"
        let other = TenantKeychainStore(service: otherService)
        defer { try? other.delete(account: "alpha") }

        try store.write(Data("self".utf8), account: "alpha")
        XCTAssertNil(try other.read(account: "alpha"))
    }
}
