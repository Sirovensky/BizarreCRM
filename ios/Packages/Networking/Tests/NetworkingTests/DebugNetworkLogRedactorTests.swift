import XCTest
@testable import Networking

// §28.7 Logging redaction — DebugNetworkLogRedactor tests

final class DebugNetworkLogRedactorTests: XCTestCase {

    // MARK: - Header redaction

    func test_redactHeaders_replacesAuthorizationBearer() {
        let input = ["Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig"]
        let out = DebugNetworkLogRedactor.redact(headers: input)
        XCTAssertEqual(out["Authorization"], "Bearer <redacted-token len=37>")
    }

    func test_redactHeaders_replacesBasicAuth() {
        let input = ["Authorization": "Basic dXNlcjpwYXNz"]
        let out = DebugNetworkLogRedactor.redact(headers: input)
        XCTAssertEqual(out["Authorization"], "Basic <redacted-token len=12>")
    }

    func test_redactHeaders_caseInsensitive() {
        let input = ["authorization": "Bearer abc"]
        let out = DebugNetworkLogRedactor.redact(headers: input)
        XCTAssertEqual(out["authorization"], "Bearer <redacted-token len=3>")
    }

    func test_redactHeaders_preservesNonSecretHeaders() {
        let input = [
            "Authorization": "Bearer secret",
            "Accept":        "application/json",
            "X-Origin":      "ios",
        ]
        let out = DebugNetworkLogRedactor.redact(headers: input)
        XCTAssertEqual(out["Accept"], "application/json")
        XCTAssertEqual(out["X-Origin"], "ios")
        XCTAssertEqual(out["Authorization"], "Bearer <redacted-token len=6>")
    }

    func test_redactHeaders_redactsCookieAndApiKey() {
        let input = [
            "Cookie":      "session=abc; foo=bar",
            "X-Api-Key":   "k_LIVE_1234",
            "Set-Cookie":  "x=y; Path=/",
        ]
        let out = DebugNetworkLogRedactor.redact(headers: input)
        XCTAssertEqual(out["Cookie"], "<redacted-cookie len=20>")
        XCTAssertEqual(out["X-Api-Key"], "<redacted-x-api-key>")
        XCTAssertEqual(out["Set-Cookie"], "<redacted-set-cookie len=11>")
    }

    func test_redactHeaders_emptyDictionary_returnsEmpty() {
        XCTAssertTrue(DebugNetworkLogRedactor.redact(headers: [:]).isEmpty)
    }

    // MARK: - Per-header redactValue

    func test_redactValue_authorizationWithoutSpace() {
        let out = DebugNetworkLogRedactor.redactValue(forHeader: "Authorization", value: "abcdef")
        XCTAssertEqual(out, "<redacted-authorization len=6>")
    }

    func test_redactValue_unknownHeader_returnsOriginal() {
        let out = DebugNetworkLogRedactor.redactValue(forHeader: "Accept", value: "application/json")
        XCTAssertEqual(out, "application/json")
    }

    // MARK: - URL query redaction

    func test_redactURL_redactsTokenQuery() {
        let url = URL(string: "https://api.example.com/path?token=secret123&page=2")!
        let out = DebugNetworkLogRedactor.redact(url: url)
        XCTAssertTrue(out.contains("token=%3Credacted%3E") || out.contains("token=<redacted>"))
        XCTAssertTrue(out.contains("page=2"))
    }

    func test_redactURL_redactsMultipleSecretParams() {
        let url = URL(string: "https://api.example.com/p?api_key=KKK&access_token=AAA&keep=ok")!
        let out = DebugNetworkLogRedactor.redact(url: url)
        XCTAssertFalse(out.contains("KKK"))
        XCTAssertFalse(out.contains("AAA"))
        XCTAssertTrue(out.contains("keep=ok"))
    }

    func test_redactURL_noQuery_returnsOriginal() {
        let url = URL(string: "https://api.example.com/path")!
        let out = DebugNetworkLogRedactor.redact(url: url)
        XCTAssertEqual(out, "https://api.example.com/path")
    }
}
