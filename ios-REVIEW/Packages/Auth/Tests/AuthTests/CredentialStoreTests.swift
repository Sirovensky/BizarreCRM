import XCTest
@testable import Auth

/// §2 Remember-me — CredentialStore unit tests.
/// Uses `InMemoryEmailStorage` so no real Keychain writes occur.
final class CredentialStoreTests: XCTestCase {

    // MARK: - lastEmail — empty on first use

    func test_lastEmail_returnsNilWhenNothingStored() async {
        let store = makeStore()
        let email = await store.lastEmail()
        XCTAssertNil(email)
    }

    // MARK: - rememberEmail / lastEmail round-trip

    func test_rememberEmail_persists_andLastEmailReturnsIt() async throws {
        let store = makeStore()
        try await store.rememberEmail("alice@example.com")
        let email = await store.lastEmail()
        XCTAssertEqual(email, "alice@example.com")
    }

    func test_rememberEmail_trimsWhitespace() async throws {
        let store = makeStore()
        try await store.rememberEmail("  bob@example.com  ")
        let email = await store.lastEmail()
        XCTAssertEqual(email, "bob@example.com")
    }

    func test_rememberEmail_overwritesPreviousEmail() async throws {
        let store = makeStore()
        try await store.rememberEmail("first@example.com")
        try await store.rememberEmail("second@example.com")
        let email = await store.lastEmail()
        XCTAssertEqual(email, "second@example.com")
    }

    // MARK: - rememberEmail validation

    func test_rememberEmail_emptyString_throws() async {
        let store = makeStore()
        do {
            try await store.rememberEmail("")
            XCTFail("Expected CredentialStoreError.emptyEmail")
        } catch CredentialStoreError.emptyEmail {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_rememberEmail_whitespaceOnly_throws() async {
        let store = makeStore()
        do {
            try await store.rememberEmail("   ")
            XCTFail("Expected CredentialStoreError.emptyEmail")
        } catch CredentialStoreError.emptyEmail {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - forget

    func test_forget_clearsStoredEmail() async throws {
        let store = makeStore()
        try await store.rememberEmail("user@example.com")
        try await store.forget()
        let email = await store.lastEmail()
        XCTAssertNil(email)
    }

    func test_forget_whenNothingStored_doesNotThrow() async {
        let store = makeStore()
        // Should not throw even when there's nothing to remove.
        do {
            try await store.forget()
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    // MARK: - Helper

    private func makeStore() -> CredentialStore {
        CredentialStore(storage: InMemoryEmailStorage())
    }
}
