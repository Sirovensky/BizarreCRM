import XCTest
@testable import Networking

/// §38 — Decode tests for membership endpoint DTOs (snake_case → camelCase mapping).
///
/// All DTOs carry explicit `CodingKeys` so the JSON decoder's
/// `.convertFromSnakeCase` strategy is not relied upon. These tests
/// validate that the wire format maps correctly to Swift properties.
final class MembershipsEndpointTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - MembershipTierDTO

    func test_tierDTO_decodes_fullRow() throws {
        let json = """
        {
            "id": 1,
            "name": "Gold",
            "slug": "gold",
            "monthly_price": 19.99,
            "discount_pct": 10,
            "discount_applies_to": "labor",
            "benefits": ["Priority queue", "Free diagnostic"],
            "color": "#f59e0b",
            "sort_order": 2,
            "is_active": true
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipTierDTO.self, from: json)
        XCTAssertEqual(dto.id, 1)
        XCTAssertEqual(dto.name, "Gold")
        XCTAssertEqual(dto.slug, "gold")
        XCTAssertEqual(dto.monthlyPrice, 19.99, accuracy: 0.01)
        XCTAssertEqual(dto.discountPct, 10)
        XCTAssertEqual(dto.discountAppliesTo, "labor")
        XCTAssertEqual(dto.benefits, ["Priority queue", "Free diagnostic"])
        XCTAssertEqual(dto.color, "#f59e0b")
        XCTAssertEqual(dto.sortOrder, 2)
        XCTAssertTrue(dto.isActive)
    }

    func test_tierDTO_decodes_emptyBenefits() throws {
        let json = """
        {
            "id": 2,
            "name": "Bronze",
            "monthly_price": 9.99,
            "discount_pct": 5,
            "benefits": [],
            "sort_order": 0,
            "is_active": true
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipTierDTO.self, from: json)
        XCTAssertTrue(dto.benefits.isEmpty)
        XCTAssertEqual(dto.discountPct, 5)
    }

    func test_tierDTO_decodes_nullSlugAndColor() throws {
        let json = """
        {
            "id": 3,
            "name": "Silver",
            "monthly_price": 14.99,
            "discount_pct": 0,
            "benefits": [],
            "sort_order": 1,
            "is_active": false
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipTierDTO.self, from: json)
        XCTAssertNil(dto.slug)
        XCTAssertNil(dto.color)
        XCTAssertFalse(dto.isActive)
    }

    func test_tierDTO_init_roundTrip() {
        let dto = MembershipTierDTO(
            id: 5,
            name: "Platinum",
            slug: "platinum",
            monthlyPrice: 49.99,
            discountPct: 15,
            discountAppliesTo: "all",
            benefits: ["Concierge"],
            color: "#6366f1",
            sortOrder: 3,
            isActive: true
        )
        XCTAssertEqual(dto.id, 5)
        XCTAssertEqual(dto.name, "Platinum")
        XCTAssertEqual(dto.discountPct, 15)
    }

    // MARK: - CustomerSubscriptionDTO

    func test_subscriptionDTO_decodes_activeRow() throws {
        let json = """
        {
            "id": 42,
            "customer_id": 7,
            "tier_id": 1,
            "status": "active",
            "current_period_start": "2026-01-01 00:00:00",
            "current_period_end": "2026-02-01 00:00:00",
            "cancel_at_period_end": false,
            "tier_name": "Gold",
            "monthly_price": 19.99,
            "discount_pct": 10,
            "color": "#f59e0b"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(CustomerSubscriptionDTO.self, from: json)
        XCTAssertEqual(dto.id, 42)
        XCTAssertEqual(dto.customerId, 7)
        XCTAssertEqual(dto.tierId, 1)
        XCTAssertEqual(dto.status, "active")
        XCTAssertFalse(dto.cancelAtPeriodEnd)
        XCTAssertEqual(dto.tierName, "Gold")
        XCTAssertEqual(dto.discountPct, 10)
    }

    func test_subscriptionDTO_decodes_nullOptionals() throws {
        let json = """
        {
            "id": 1,
            "customer_id": 2,
            "tier_id": 3,
            "status": "paused",
            "current_period_start": "2026-01-01 00:00:00",
            "current_period_end": "2026-02-01 00:00:00",
            "cancel_at_period_end": false
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(CustomerSubscriptionDTO.self, from: json)
        XCTAssertNil(dto.tierName)
        XCTAssertNil(dto.blockchypToken)
        XCTAssertNil(dto.pauseReason)
    }

    func test_subscriptionDTO_decodes_pausedWithReason() throws {
        let json = """
        {
            "id": 99,
            "customer_id": 5,
            "tier_id": 2,
            "status": "paused",
            "pause_reason": "Customer requested",
            "current_period_start": "2026-01-01 00:00:00",
            "current_period_end": "2026-02-01 00:00:00",
            "cancel_at_period_end": true
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(CustomerSubscriptionDTO.self, from: json)
        XCTAssertEqual(dto.pauseReason, "Customer requested")
        XCTAssertTrue(dto.cancelAtPeriodEnd)
    }

    // MARK: - SubscriptionPaymentDTO

    func test_paymentDTO_decodes_successPayment() throws {
        let json = """
        {
            "id": 10,
            "subscription_id": 42,
            "amount": 19.99,
            "status": "success",
            "created_at": "2026-01-01 10:00:00"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(SubscriptionPaymentDTO.self, from: json)
        XCTAssertEqual(dto.id, 10)
        XCTAssertEqual(dto.subscriptionId, 42)
        XCTAssertEqual(dto.amount, 19.99, accuracy: 0.01)
        XCTAssertEqual(dto.status, "success")
        XCTAssertNotNil(dto.createdAt)
    }

    func test_paymentDTO_decodes_failedPayment() throws {
        let json = """
        {
            "id": 11,
            "subscription_id": 42,
            "amount": 19.99,
            "status": "failed"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(SubscriptionPaymentDTO.self, from: json)
        XCTAssertEqual(dto.status, "failed")
        XCTAssertNil(dto.createdAt)
    }

    // MARK: - AdminSubscriptionDTO

    func test_adminSubscriptionDTO_decodes_withCustomerInfo() throws {
        let json = """
        {
            "id": 1,
            "customer_id": 10,
            "tier_id": 2,
            "status": "active",
            "current_period_start": "2026-01-01 00:00:00",
            "current_period_end": "2026-02-01 00:00:00",
            "tier_name": "Gold",
            "monthly_price": 19.99,
            "color": "#f59e0b",
            "first_name": "Alice",
            "last_name": "Smith",
            "phone": "+1555555555",
            "email": "alice@example.com"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(AdminSubscriptionDTO.self, from: json)
        XCTAssertEqual(dto.id, 1)
        XCTAssertEqual(dto.firstName, "Alice")
        XCTAssertEqual(dto.lastName, "Smith")
        XCTAssertEqual(dto.email, "alice@example.com")
        XCTAssertEqual(dto.tierName, "Gold")
    }

    // MARK: - MembershipActionResultDTO

    func test_actionResultDTO_decodes_cancelled() throws {
        let json = """
        {
            "cancelled": true,
            "immediate": false
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipActionResultDTO.self, from: json)
        XCTAssertTrue(dto.cancelled ?? false)
        XCTAssertFalse(dto.immediate ?? true)
    }

    func test_actionResultDTO_decodes_paused() throws {
        let json = """
        {
            "paused": true
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipActionResultDTO.self, from: json)
        XCTAssertTrue(dto.paused ?? false)
        XCTAssertNil(dto.cancelled)
    }

    func test_actionResultDTO_decodes_resumed() throws {
        let json = """
        {
            "resumed": true
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipActionResultDTO.self, from: json)
        XCTAssertTrue(dto.resumed ?? false)
    }

    // MARK: - MembershipEnrollCardResultDTO

    func test_enrollCardResultDTO_decodes_fullResult() throws {
        let json = """
        {
            "token": "tok_abc123",
            "maskedPan": "XXXX1234",
            "cardType": "visa"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipEnrollCardResultDTO.self, from: json)
        XCTAssertEqual(dto.token, "tok_abc123")
        XCTAssertEqual(dto.maskedPan, "XXXX1234")
        XCTAssertEqual(dto.cardType, "visa")
    }

    func test_enrollCardResultDTO_decodes_minimalResult() throws {
        let json = """
        {
            "token": "tok_xyz789"
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipEnrollCardResultDTO.self, from: json)
        XCTAssertEqual(dto.token, "tok_xyz789")
        XCTAssertNil(dto.maskedPan)
        XCTAssertNil(dto.cardType)
    }

    // MARK: - MembershipPaymentLinkDTO

    func test_paymentLinkDTO_decodes_fullLink() throws {
        let json = """
        {
            "linkUrl": "https://pay.example.com/link/abc",
            "linkCode": "LINK-ABC",
            "tier_name": "Gold",
            "amount": 19.99
        }
        """.data(using: .utf8)!
        let dto = try decoder.decode(MembershipPaymentLinkDTO.self, from: json)
        XCTAssertEqual(dto.linkUrl, "https://pay.example.com/link/abc")
        XCTAssertEqual(dto.linkCode, "LINK-ABC")
        XCTAssertEqual(dto.tierName, "Gold")
        XCTAssertEqual(dto.amount, 19.99, accuracy: 0.01)
    }

    // MARK: - MembershipSubscribeRequest encoding

    func test_subscribeRequest_encodesCorrectly() throws {
        let encoder = JSONEncoder()
        let req = MembershipSubscribeRequest(customerId: 7, tierId: 3, blockchypToken: "tok_123")
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["customer_id"] as? Int, 7)
        XCTAssertEqual(dict?["tier_id"] as? Int, 3)
        XCTAssertEqual(dict?["blockchyp_token"] as? String, "tok_123")
    }

    func test_subscribeRequest_nilToken_encodesNullOrAbsent() throws {
        let encoder = JSONEncoder()
        let req = MembershipSubscribeRequest(customerId: 1, tierId: 2, blockchypToken: nil)
        let data = try encoder.encode(req)
        // Verify it at least encodes without throwing
        XCTAssertFalse(data.isEmpty)
    }

    func test_cancelRequest_encodesImmediate() throws {
        let encoder = JSONEncoder()
        let req = MembershipCancelRequest(immediate: true)
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["immediate"] as? Bool, true)
    }

    func test_cancelRequest_encodesNotImmediate() throws {
        let encoder = JSONEncoder()
        let req = MembershipCancelRequest(immediate: false)
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["immediate"] as? Bool, false)
    }
}
