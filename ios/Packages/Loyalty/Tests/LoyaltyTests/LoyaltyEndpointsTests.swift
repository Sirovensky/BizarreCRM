import XCTest
@testable import Networking

/// §38 — Decode tests for `LoyaltyBalance` and `LoyaltyPassInfo` DTOs.
/// Validates snake_case key mapping used on the wire.
final class LoyaltyEndpointsTests: XCTestCase {

    // DTOs declare explicit CodingKeys with snake_case strings, so the
    // decoder should NOT apply convertFromSnakeCase — that would double-
    // transform the key and fail to find "customer_id" in the JSON.
    // This matches the production path: APIClientImpl uses convertFromSnakeCase
    // as a default, but explicit CodingKeys override the mapping so the
    // raw JSON key is matched directly against CodingKeys.stringValue.
    private let decoder = JSONDecoder()

    // MARK: - LoyaltyBalance decode

    func test_loyaltyBalance_decodes_allFields() throws {
        let json = """
        {
            "customer_id": 42,
            "points": 1500,
            "tier": "gold",
            "lifetime_spend_cents": 250000,
            "member_since": "2023-01-15"
        }
        """.data(using: .utf8)!

        let balance = try decoder.decode(LoyaltyBalance.self, from: json)

        XCTAssertEqual(balance.customerId, 42)
        XCTAssertEqual(balance.points, 1500)
        XCTAssertEqual(balance.tier, "gold")
        XCTAssertEqual(balance.lifetimeSpendCents, 250000)
        XCTAssertEqual(balance.memberSince, "2023-01-15")
    }

    func test_loyaltyBalance_decodes_bronze_tier() throws {
        let json = """
        {
            "customer_id": 1,
            "points": 50,
            "tier": "bronze",
            "lifetime_spend_cents": 0,
            "member_since": "2024-06-01"
        }
        """.data(using: .utf8)!

        let balance = try decoder.decode(LoyaltyBalance.self, from: json)
        XCTAssertEqual(balance.tier, "bronze")
        XCTAssertEqual(balance.points, 50)
    }

    func test_loyaltyBalance_decodes_platinum_tier() throws {
        let json = """
        {
            "customer_id": 99,
            "points": 99999,
            "tier": "platinum",
            "lifetime_spend_cents": 5000000,
            "member_since": "2020-03-01"
        }
        """.data(using: .utf8)!

        let balance = try decoder.decode(LoyaltyBalance.self, from: json)
        XCTAssertEqual(balance.tier, "platinum")
        XCTAssertEqual(balance.lifetimeSpendCents, 5000000)
    }

    func test_loyaltyBalance_zero_points() throws {
        let json = """
        {
            "customer_id": 7,
            "points": 0,
            "tier": "silver",
            "lifetime_spend_cents": 100,
            "member_since": "2025-01-01"
        }
        """.data(using: .utf8)!

        let balance = try decoder.decode(LoyaltyBalance.self, from: json)
        XCTAssertEqual(balance.points, 0)
    }

    // MARK: - LoyaltyPassInfo decode

    func test_loyaltyPassInfo_decodes_allFields() throws {
        let json = """
        {
            "customer_id": 42,
            "pass_url": "https://example.com/passes/abc123.pkpass",
            "barcode": "BARCODE-UUID-1234"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(LoyaltyPassInfo.self, from: json)

        XCTAssertEqual(info.customerId, 42)
        XCTAssertEqual(info.passUrl, "https://example.com/passes/abc123.pkpass")
        XCTAssertEqual(info.barcode, "BARCODE-UUID-1234")
    }

    func test_loyaltyPassInfo_decodes_nullOptionals() throws {
        let json = """
        {
            "customer_id": 7,
            "pass_url": null,
            "barcode": null
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(LoyaltyPassInfo.self, from: json)

        XCTAssertEqual(info.customerId, 7)
        XCTAssertNil(info.passUrl)
        XCTAssertNil(info.barcode)
    }

    func test_loyaltyPassInfo_decodes_missingOptionals() throws {
        let json = """
        {
            "customer_id": 3
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(LoyaltyPassInfo.self, from: json)

        XCTAssertEqual(info.customerId, 3)
        XCTAssertNil(info.passUrl)
        XCTAssertNil(info.barcode)
    }

    // MARK: - Init / equatable sanity

    func test_loyaltyBalance_init_roundTrip() throws {
        let balance = LoyaltyBalance(
            customerId: 10,
            points: 300,
            tier: "silver",
            lifetimeSpendCents: 30000,
            memberSince: "2022-11-01"
        )
        XCTAssertEqual(balance.customerId, 10)
        XCTAssertEqual(balance.tier, "silver")
    }

    func test_loyaltyPassInfo_init_roundTrip() throws {
        let info = LoyaltyPassInfo(
            customerId: 5,
            passUrl: "https://example.com/pass.pkpass",
            barcode: "ABC123"
        )
        XCTAssertEqual(info.passUrl, "https://example.com/pass.pkpass")
        XCTAssertEqual(info.barcode, "ABC123")
    }
}
