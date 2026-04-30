import XCTest
@testable import Persistence

/// §1.3 Random encryption passphrase, persisted in Keychain.
///
/// Uses the real Keychain (same pattern as `KeychainStoreTests`). On
/// simulators where Keychain access fails (rare — usually a
/// signing-identity issue), the tests `XCTSkip` rather than hard-fail.
final class DatabasePassphraseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Start each test from a clean slate so `loadOrCreate()` has to
        // generate a fresh value rather than read a left-over one from a
        // previous run.
        try? KeychainStore.shared.remove(.dbPassphrase)
    }

    override func tearDown() {
        try? KeychainStore.shared.remove(.dbPassphrase)
        super.tearDown()
    }

    // MARK: - loadOrCreate

    func test_loadOrCreate_returnsStableValueAcrossCalls() throws {
        let first: String
        do {
            first = try DatabasePassphrase.loadOrCreate()
        } catch {
            throw XCTSkip("Keychain unavailable in this test environment: \(error)")
        }
        let second = try DatabasePassphrase.loadOrCreate()
        XCTAssertEqual(first, second,
            "Subsequent calls must return the cached Keychain value, not regenerate")
    }

    func test_loadOrCreate_returns64HexCharacters() throws {
        let pass: String
        do {
            pass = try DatabasePassphrase.loadOrCreate()
        } catch {
            throw XCTSkip("Keychain unavailable in this test environment: \(error)")
        }
        XCTAssertEqual(pass.count, 64,
            "32-byte key hex-encoded must be exactly 64 characters")
        XCTAssertTrue(DatabasePassphrase.isHexPassphrase(pass),
            "Passphrase must consist solely of lowercase hex digits")
    }

    func test_loadOrCreate_freshInvocationsProduceDifferentValues() throws {
        let first: String
        do {
            first = try DatabasePassphrase.loadOrCreate()
        } catch {
            throw XCTSkip("Keychain unavailable in this test environment: \(error)")
        }
        try KeychainStore.shared.remove(.dbPassphrase)
        let second = try DatabasePassphrase.loadOrCreate()
        // Two independent 256-bit random draws — collision probability is
        // negligibly small (≈1/2^256).
        XCTAssertNotEqual(first, second,
            "After Keychain wipe, loadOrCreate must mint a new random key")
    }

    // MARK: - generateHexPassphrase (pure)

    func test_generateHexPassphrase_isAlways64HexChars() throws {
        for _ in 0..<16 {
            let hex = try DatabasePassphrase.generateHexPassphrase()
            XCTAssertEqual(hex.count, 64)
            XCTAssertTrue(DatabasePassphrase.isHexPassphrase(hex))
        }
    }

    // MARK: - isHexPassphrase

    func test_isHexPassphrase_rejectsWrongLength() {
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase(""))
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase("abc"))
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase(String(repeating: "a", count: 63)))
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase(String(repeating: "a", count: 65)))
    }

    func test_isHexPassphrase_rejectsUppercaseAndNonHex() {
        let upper = String(repeating: "A", count: 64)
        let bad   = String(repeating: "z", count: 64)
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase(upper),
            "Generator emits lowercase only; uppercase is rejected to keep the contract crisp")
        XCTAssertFalse(DatabasePassphrase.isHexPassphrase(bad))
    }

    func test_isHexPassphrase_acceptsValidLowercaseHex() {
        let valid = String(repeating: "0123456789abcdef", count: 4)
        XCTAssertEqual(valid.count, 64)
        XCTAssertTrue(DatabasePassphrase.isHexPassphrase(valid))
    }
}
