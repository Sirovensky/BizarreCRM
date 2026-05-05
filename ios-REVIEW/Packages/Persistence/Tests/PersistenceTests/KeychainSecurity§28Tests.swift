import XCTest
@testable import Persistence

// §28 Security batch — KeychainStore tests
//
// These tests exercise `deleteUserScoped(tenantSlug:)`, which was shipped as
// part of the §28.1 logout-cleanup work.  Because `KeychainStore.shared` uses
// the real KeychainAccess backend (no dependency injection seam), the tests
// pre-populate real Keychain items under the `com.bizarrecrm` service, call
// `deleteUserScoped`, and then assert the expected presence / absence of each
// key.  `tearDown` calls `clearAll()` to keep the simulator Keychain clean.

final class KeychainSecurity§28Tests: XCTestCase {

    // MARK: - Lifecycle

    override func setUp() async throws {
        // Ensure a clean slate before each test.
        KeychainStore.shared.clearAll()
    }

    override func tearDown() async throws {
        // Leave no test artefacts in the Keychain.
        KeychainStore.shared.clearAll()
    }

    // MARK: - Test 1: deleteUserScoped removes session credentials

    /// `deleteUserScoped` must erase `accessToken`, `refreshToken`, and `pinHash`
    /// so they cannot be recovered after sign-out.
    func test_deleteUserScoped_removesAccessToken_refreshToken_pinHash() throws {
        // Arrange — seed the three credential keys.
        try KeychainStore.shared.set("tok_access",  for: .accessToken)
        try KeychainStore.shared.set("tok_refresh", for: .refreshToken)
        try KeychainStore.shared.set("hash_pin",    for: .pinHash)

        // Act
        KeychainStore.shared.deleteUserScoped()

        // Assert — all three are gone.
        XCTAssertNil(KeychainStore.shared.get(.accessToken),
                     "accessToken must be deleted on user-scoped wipe")
        XCTAssertNil(KeychainStore.shared.get(.refreshToken),
                     "refreshToken must be deleted on user-scoped wipe")
        XCTAssertNil(KeychainStore.shared.get(.pinHash),
                     "pinHash must be deleted on user-scoped wipe")
    }

    // MARK: - Test 2: deleteUserScoped preserves rememberedEmail

    /// `rememberedEmail` is the login pre-fill convenience value.  It is
    /// explicitly excluded from `userScopedKeys` so it survives sign-out.
    func test_deleteUserScoped_preservesRememberedEmail() throws {
        // Arrange
        try KeychainStore.shared.set("alice@example.com", for: .rememberedEmail)
        try KeychainStore.shared.set("tok_access", for: .accessToken)

        // Act
        KeychainStore.shared.deleteUserScoped()

        // Assert — email preserved, token gone.
        XCTAssertEqual(KeychainStore.shared.get(.rememberedEmail), "alice@example.com",
                       "rememberedEmail must survive deleteUserScoped")
        XCTAssertNil(KeychainStore.shared.get(.accessToken),
                     "accessToken must be deleted even when rememberedEmail is set")
    }

    // MARK: - Test 3: deleteUserScoped is idempotent

    /// Calling `deleteUserScoped` twice must not throw or crash — the second
    /// call is a no-op because the items are already absent.
    func test_deleteUserScoped_isIdempotent_doesNotCrash() throws {
        // Arrange — seed one key so first call has something to remove.
        try KeychainStore.shared.set("tok_access", for: .accessToken)

        // Act — two successive calls; neither should throw or produce a crash.
        KeychainStore.shared.deleteUserScoped()
        KeychainStore.shared.deleteUserScoped() // second call on empty set

        // Assert — nothing to verify beyond "no crash"; key is still absent.
        XCTAssertNil(KeychainStore.shared.get(.accessToken))
    }

    // MARK: - Test 4: deleteUserScoped removes all declared userScopedKeys

    /// Verify every key in `userScopedKeys` is cleared, not just the three
    /// checked in Test 1.  This guards against future additions to the list
    /// being accidentally omitted from the wipe.
    func test_deleteUserScoped_removesAllDeclaredUserScopedKeys() throws {
        // Arrange — write a sentinel value to every key that should be wiped.
        let scopedKeys: [KeychainKey] = [
            .accessToken,
            .refreshToken,
            .pinHash,
            .pinLength,
            .pinFailCount,
            .pinLockUntil,
            .dbPassphrase,
            .backupCodes,
            .blockChypAuth,
            .activeTenantId,
        ]
        for key in scopedKeys {
            try KeychainStore.shared.set("value_\(key.rawValue)", for: key)
        }

        // Act
        KeychainStore.shared.deleteUserScoped()

        // Assert — every scoped key is absent.
        for key in scopedKeys {
            XCTAssertNil(
                KeychainStore.shared.get(key),
                "\(key.rawValue) must be nil after deleteUserScoped"
            )
        }
    }

    // MARK: - Test 5: deleteUserScoped(tenantSlug:) accepts a slug parameter without crashing

    /// The public API accepts an optional `tenantSlug` for future per-tenant
    /// isolation.  Passing a non-nil slug must complete without error.
    func test_deleteUserScoped_withTenantSlug_doesNotCrash() throws {
        try KeychainStore.shared.set("tok_access", for: .accessToken)

        // Must not crash even with a slug passed.
        KeychainStore.shared.deleteUserScoped(tenantSlug: "acme-corp")

        XCTAssertNil(KeychainStore.shared.get(.accessToken))
    }
}
