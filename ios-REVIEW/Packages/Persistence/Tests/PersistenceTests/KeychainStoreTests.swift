import XCTest
@testable import Persistence

// §28.12 Unit tests for per-tenant DB passphrase. Uses the real Keychain
// (same pattern as PINStoreTests). Tests clean up their keys in tearDown.

final class KeychainStoreTests: XCTestCase {

    private let testSlug = "test-tenant-\(UUID().uuidString)"

    override func tearDown() {
        // Remove any passphrase the test created so subsequent runs start clean.
        try? KeychainStore.shared.removeTenantPassphrase(for: testSlug)
    }

    // MARK: — tenantPassphrase

    func test_tenantPassphrase_generatesOnFirstCall() throws {
        let pass = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        XCTAssertFalse(pass.isEmpty)
    }

    func test_tenantPassphrase_returnsSameValueOnSubsequentCalls() throws {
        let first  = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        let second = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        XCTAssertEqual(first, second)
    }

    func test_tenantPassphrase_differentSlugsProduceDifferentKeys() throws {
        let slugA = testSlug + "-A"
        let slugB = testSlug + "-B"
        defer {
            try? KeychainStore.shared.removeTenantPassphrase(for: slugA)
            try? KeychainStore.shared.removeTenantPassphrase(for: slugB)
        }
        let passA = try KeychainStore.shared.tenantPassphrase(for: slugA)
        let passB = try KeychainStore.shared.tenantPassphrase(for: slugB)
        XCTAssertNotEqual(passA, passB,
            "Each tenant must get its own independent passphrase (§28.12)")
    }

    func test_tenantPassphrase_is256bitBase64() throws {
        let pass = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        // 32 bytes Base64 → ceil(32/3)*4 = 44 chars (with '==' padding).
        let decoded = Data(base64Encoded: pass)
        XCTAssertNotNil(decoded, "Passphrase must be valid Base64")
        XCTAssertEqual(decoded?.count, 32,
            "Passphrase must be exactly 32 bytes (256-bit) per §28.12")
    }

    // MARK: — removeTenantPassphrase

    func test_removeTenantPassphrase_causesNewPassphraseOnNextCall() throws {
        let first = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        try KeychainStore.shared.removeTenantPassphrase(for: testSlug)
        let second = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        // Statistically guaranteed: two independent 256-bit random values differ.
        XCTAssertNotEqual(first, second,
            "After removal, a new passphrase must be generated")
    }

    // MARK: — deleteSessionKeys does NOT touch tenant passphrases

    func test_deleteSessionKeys_doesNotRemoveTenantPassphrase() throws {
        let pass = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        KeychainStore.shared.deleteSessionKeys()
        let passAfter = try KeychainStore.shared.tenantPassphrase(for: testSlug)
        XCTAssertEqual(pass, passAfter,
            "Logout must not wipe per-tenant DB passphrase (§28.1 comment)")
    }
}
