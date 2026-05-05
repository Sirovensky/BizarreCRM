import XCTest
@testable import Auth

// MARK: - PINHasher tests

final class PinHasherTests: XCTestCase {

    // MARK: - generateSalt

    func test_generateSalt_returnsNonEmptyBase64String() {
        let salt = PINHasher.generateSalt()
        XCTAssertFalse(salt.isEmpty)
        // Must be valid base64.
        XCTAssertNotNil(Data(base64Encoded: salt), "Salt should be valid base64")
    }

    func test_generateSalt_producesUniqueValues() {
        let s1 = PINHasher.generateSalt()
        let s2 = PINHasher.generateSalt()
        XCTAssertNotEqual(s1, s2, "Two generated salts should not collide")
    }

    func test_generateSalt_decodesTo16Bytes() {
        let salt = PINHasher.generateSalt()
        let data = Data(base64Encoded: salt)
        XCTAssertEqual(data?.count, 16)
    }

    // MARK: - hash

    func test_hash_returnsDeterministicResult() {
        let hash1 = PINHasher.hash(pin: "1234", salt: "fixedSalt==")
        let hash2 = PINHasher.hash(pin: "1234", salt: "fixedSalt==")
        XCTAssertEqual(hash1, hash2)
    }

    func test_hash_returnsHexString() {
        let hash = PINHasher.hash(pin: "1234", salt: "abc")
        // SHA-256 produces 32 bytes = 64 hex chars.
        XCTAssertEqual(hash.count, 64)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    func test_hash_differsForDifferentPins() {
        let salt = "sameSalt=="
        let h1 = PINHasher.hash(pin: "1234", salt: salt)
        let h2 = PINHasher.hash(pin: "5678", salt: salt)
        XCTAssertNotEqual(h1, h2)
    }

    func test_hash_differsForDifferentSalts() {
        let h1 = PINHasher.hash(pin: "1234", salt: "salt1==")
        let h2 = PINHasher.hash(pin: "1234", salt: "salt2==")
        XCTAssertNotEqual(h1, h2)
    }

    // MARK: - verify

    func test_verify_returnsTrueForCorrectPin() {
        let salt = PINHasher.generateSalt()
        let hash = PINHasher.hash(pin: "1234", salt: salt)
        let entry = makeEntry(id: 1, pinSalt: salt, pinHash: hash)
        XCTAssertTrue(PINHasher.verify(pin: "1234", entry: entry))
    }

    func test_verify_returnsFalseForWrongPin() {
        let salt = PINHasher.generateSalt()
        let hash = PINHasher.hash(pin: "1234", salt: salt)
        let entry = makeEntry(id: 1, pinSalt: salt, pinHash: hash)
        XCTAssertFalse(PINHasher.verify(pin: "9999", entry: entry))
    }

    func test_verify_returnsFalseForTamperedHash() {
        let salt = PINHasher.generateSalt()
        let entry = makeEntry(id: 1, pinSalt: salt, pinHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertFalse(PINHasher.verify(pin: "1234", entry: entry))
    }

    // MARK: - helpers

    private func makeEntry(id: Int, pinSalt: String, pinHash: String) -> RosterEntry {
        RosterEntry(
            id: id,
            username: "u\(id)",
            displayName: "User \(id)",
            email: "u\(id)@test.com",
            role: "staff",
            avatarUrl: nil,
            pinSalt: pinSalt,
            pinHash: pinHash
        )
    }
}
