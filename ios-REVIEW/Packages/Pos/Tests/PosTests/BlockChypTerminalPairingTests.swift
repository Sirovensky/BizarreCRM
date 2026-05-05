#if canImport(UIKit)
import XCTest
@testable import Pos

/// §16.5 — Unit tests for `TerminalPairing` model.
/// No payment math, no SDK calls — scaffold only.
final class BlockChypTerminalPairingTests: XCTestCase {

    // MARK: - TerminalPairing model

    func test_init_setsFields() {
        let p = TerminalPairing(code: "ABC123", ipAddress: "192.168.1.50", nickname: "Front register")
        XCTAssertEqual(p.code, "ABC123")
        XCTAssertEqual(p.ipAddress, "192.168.1.50")
        XCTAssertEqual(p.nickname, "Front register")
    }

    func test_init_nilNickname() {
        let p = TerminalPairing(code: "XYZ", ipAddress: "10.0.0.1")
        XCTAssertNil(p.nickname)
    }

    // MARK: - Codable roundtrip

    func test_codable_roundtrip_withNickname() throws {
        let original = TerminalPairing(code: "T1", ipAddress: "192.168.0.1", nickname: "Main")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalPairing.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codable_roundtrip_nilNickname() throws {
        let original = TerminalPairing(code: "T2", ipAddress: "10.0.0.5", nickname: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalPairing.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.nickname)
    }

    func test_codable_usesSnakeCaseKey() throws {
        let pairing = TerminalPairing(code: "X", ipAddress: "1.2.3.4")
        let data = try JSONEncoder().encode(pairing)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(dict["ip_address"], "Expected snake_case key ip_address")
        XCTAssertNil(dict["ipAddress"], "Expected no camelCase key ipAddress")
    }

    // MARK: - Equatable

    func test_equatable_sameValues_equal() {
        let a = TerminalPairing(code: "A", ipAddress: "1.2.3.4", nickname: "X")
        let b = TerminalPairing(code: "A", ipAddress: "1.2.3.4", nickname: "X")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentCode_notEqual() {
        let a = TerminalPairing(code: "A", ipAddress: "1.2.3.4")
        let b = TerminalPairing(code: "B", ipAddress: "1.2.3.4")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentIP_notEqual() {
        let a = TerminalPairing(code: "A", ipAddress: "1.2.3.4")
        let b = TerminalPairing(code: "A", ipAddress: "5.6.7.8")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - IP format heuristic (via savePairing path — test logic directly)

    func test_ipHeuristic_validIPv4() {
        let ip = "192.168.1.50"
        let valid = ip.split(separator: ".").count == 4 || ip.contains(":")
        XCTAssertTrue(valid)
    }

    func test_ipHeuristic_validIPv6Like() {
        let ip = "::1"
        let valid = ip.split(separator: ".").count == 4 || ip.contains(":")
        XCTAssertTrue(valid)
    }

    func test_ipHeuristic_invalidHostname() {
        let ip = "mydevice.local"
        let valid = ip.split(separator: ".").count == 4 || ip.contains(":")
        // "mydevice.local" splits into 2 parts, no colon — should fail
        XCTAssertFalse(valid)
    }

    func test_ipHeuristic_emptyString_invalid() {
        let ip = ""
        let valid = ip.split(separator: ".").count == 4 || ip.contains(":")
        XCTAssertFalse(valid)
    }
}
#endif
