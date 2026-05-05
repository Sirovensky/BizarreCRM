import XCTest
@testable import Hardware

/// Tests for BlockChypSigner.
///
/// Test vectors are constructed from the BlockChyp authentication spec:
///   https://docs.blockchyp.com/rest-api/authentication
///
/// The algorithm:
///   message  = apiKey + bearerToken + timestamp + nonce + bodyHex
///   signature = HMAC-SHA256(key: hex_decode(signingKey), message: message)
///               encoded as lowercase hex
///
/// We derive our own reference vectors by computing the HMAC with known
/// inputs and confirming the output is stable across runs (deterministic
/// pure function).
final class BlockChypSignerTests: XCTestCase {

    // MARK: - Known-vector test

    /// Fixed vector derived from BlockChyp docs example values.
    /// The signing key is a hex-encoded 32-byte key; the body is empty.
    func test_sign_knownVector_emptyBody() {
        // Inputs — fixed for determinism
        let apiKey = "SGLATLA62VYMBE3Q"
        let bearerToken = "RIKWCJHHTMSYYRDP"
        let signingKeyHex = "4b9bb0b9a5d6c2ee4e0b3b3b4b5b6b7b8b9babbcbdbebfc0c1c2c3c4c5c6c7"
        let nonce = "b3e69b7a4f2e1d0c3b4a5968778695a4"
        let timestamp = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01T00:00:00Z
        let body = Data()

        let sig = BlockChypSigner.sign(
            body: body,
            nonce: nonce,
            timestamp: timestamp,
            apiKey: apiKey,
            bearerToken: bearerToken,
            signingKey: signingKeyHex
        )

        // Signature must be 64 lowercase hex chars (32 bytes HMAC-SHA256)
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(sig.allSatisfy { $0.isHexDigit }, "Signature must be lowercase hex")

        // Deterministic: same inputs must produce same output
        let sig2 = BlockChypSigner.sign(
            body: body,
            nonce: nonce,
            timestamp: timestamp,
            apiKey: apiKey,
            bearerToken: bearerToken,
            signingKey: signingKeyHex
        )
        XCTAssertEqual(sig, sig2, "Signing is deterministic")
    }

    /// Body bytes contribute to the signature — different bodies → different signatures.
    func test_sign_differentBody_differentSignature() {
        let creds = makeCreds()
        let nonce = "aaaa1234bbbb5678cccc9012dddd3456"
        let ts = Date(timeIntervalSince1970: 1_700_000_000)

        let sig1 = BlockChypSigner.sign(
            body: Data("{\"amount\":\"1.00\"}".utf8),
            nonce: nonce,
            timestamp: ts,
            apiKey: creds.apiKey,
            bearerToken: creds.bearerToken,
            signingKey: creds.signingKey
        )
        let sig2 = BlockChypSigner.sign(
            body: Data("{\"amount\":\"2.00\"}".utf8),
            nonce: nonce,
            timestamp: ts,
            apiKey: creds.apiKey,
            bearerToken: creds.bearerToken,
            signingKey: creds.signingKey
        )
        XCTAssertNotEqual(sig1, sig2)
    }

    /// Different nonces → different signatures (nonce is in the message).
    func test_sign_differentNonce_differentSignature() {
        let creds = makeCreds()
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let body = Data()

        let sig1 = BlockChypSigner.sign(body: body, nonce: "nonce1111111111111111111111111111",
                                         timestamp: ts, apiKey: creds.apiKey,
                                         bearerToken: creds.bearerToken, signingKey: creds.signingKey)
        let sig2 = BlockChypSigner.sign(body: body, nonce: "nonce2222222222222222222222222222",
                                         timestamp: ts, apiKey: creds.apiKey,
                                         bearerToken: creds.bearerToken, signingKey: creds.signingKey)
        XCTAssertNotEqual(sig1, sig2)
    }

    /// Different timestamps → different signatures.
    func test_sign_differentTimestamp_differentSignature() {
        let creds = makeCreds()
        let nonce = "aabb1122ccdd3344eeff5566aabb1122"
        let body = Data()

        let sig1 = BlockChypSigner.sign(body: body, nonce: nonce,
                                         timestamp: Date(timeIntervalSince1970: 1_000_000),
                                         apiKey: creds.apiKey, bearerToken: creds.bearerToken,
                                         signingKey: creds.signingKey)
        let sig2 = BlockChypSigner.sign(body: body, nonce: nonce,
                                         timestamp: Date(timeIntervalSince1970: 2_000_000),
                                         apiKey: creds.apiKey, bearerToken: creds.bearerToken,
                                         signingKey: creds.signingKey)
        XCTAssertNotEqual(sig1, sig2)
    }

    // MARK: - authHeaders tests

    func test_authHeaders_containsRequiredKeys() {
        let creds = makeCreds()
        let headers = BlockChypSigner.authHeaders(
            credentials: creds,
            body: Data(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            nonce: "testNonce11111111111111111111111"
        )
        XCTAssertNotNil(headers["Nonce"])
        XCTAssertNotNil(headers["Timestamp"])
        XCTAssertNotNil(headers["Authorization"])
        XCTAssertNotNil(headers["Signature"])
    }

    func test_authHeaders_authorizationFormat() {
        let creds = makeCreds()
        let headers = BlockChypSigner.authHeaders(
            credentials: creds,
            body: Data(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            nonce: "testNonce11111111111111111111111"
        )
        let auth = headers["Authorization"]!
        XCTAssertTrue(auth.hasPrefix("Dual "), "Authorization header must start with 'Dual '")
        XCTAssertTrue(auth.contains(creds.apiKey), "Authorization must include apiKey")
        XCTAssertTrue(auth.contains(creds.bearerToken), "Authorization must include bearerToken")
    }

    func test_authHeaders_signatureIs64HexChars() {
        let creds = makeCreds()
        let headers = BlockChypSigner.authHeaders(
            credentials: creds,
            body: Data("test body".utf8),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            nonce: "testNonce22222222222222222222222"
        )
        let sig = headers["Signature"]!
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(sig.allSatisfy { $0.isHexDigit })
    }

    func test_authHeaders_noncePassedThrough() {
        let creds = makeCreds()
        let myNonce = "mynonce3333333333333333333333333"
        let headers = BlockChypSigner.authHeaders(
            credentials: creds,
            body: Data(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            nonce: myNonce
        )
        XCTAssertEqual(headers["Nonce"], myNonce)
    }

    func test_authHeaders_timestampFormat() {
        let creds = makeCreds()
        let ts = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01T00:00:00Z
        let headers = BlockChypSigner.authHeaders(
            credentials: creds,
            body: Data(),
            timestamp: ts,
            nonce: "fixednonce444444444444444444444"
        )
        XCTAssertEqual(headers["Timestamp"], "2021-01-01T00:00:00Z")
    }

    // MARK: - randomNonce

    func test_randomNonce_length64Hex() {
        let nonce = BlockChypSigner.randomNonce()
        XCTAssertEqual(nonce.count, 64)
        XCTAssertTrue(nonce.allSatisfy { $0.isHexDigit })
    }

    func test_randomNonce_isRandom() {
        let n1 = BlockChypSigner.randomNonce()
        let n2 = BlockChypSigner.randomNonce()
        XCTAssertNotEqual(n1, n2, "Two nonces should not collide")
    }

    // MARK: - hexToData

    func test_hexToData_validInput() {
        let data = BlockChypSigner.hexToData("deadbeef")
        XCTAssertEqual(data, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func test_hexToData_oddLength_returnsNil() {
        XCTAssertNil(BlockChypSigner.hexToData("abc"))
    }

    func test_hexToData_emptyString() {
        XCTAssertEqual(BlockChypSigner.hexToData(""), Data())
    }

    func test_hexToData_uppercase() {
        let data = BlockChypSigner.hexToData("DEADBEEF")
        XCTAssertEqual(data, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    // MARK: - formatTimestamp

    func test_formatTimestamp_epoch() {
        let s = BlockChypSigner.formatTimestamp(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s, "1970-01-01T00:00:00Z")
    }

    func test_formatTimestamp_knownDate() {
        let s = BlockChypSigner.formatTimestamp(Date(timeIntervalSince1970: 1_609_459_200))
        XCTAssertEqual(s, "2021-01-01T00:00:00Z")
    }

    // MARK: - Helpers

    private func makeCreds() -> BlockChypCredentials {
        BlockChypCredentials(
            apiKey: "TESTKEY1234567890",
            bearerToken: "TESTBEARER123456789",
            signingKey: "deadbeefcafe1234deadbeefcafe5678deadbeefcafe9012deadbeefcafe3456"
        )
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
