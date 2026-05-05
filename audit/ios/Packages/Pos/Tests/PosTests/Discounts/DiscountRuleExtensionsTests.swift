import XCTest
@testable import Pos

// MARK: - DiscountRuleExtensionsTests
//
// §16 — Tests for new DiscountRule eligibility fields:
// - first-time customer gate
// - loyalty tier gate
// - employee role gate
// - excluded categories
// - channel restriction
// - DiscountChannel / DiscountStackOrder codable round-trips

final class DiscountRuleExtensionsTests: XCTestCase {

    // MARK: - DiscountChannel

    func test_discountChannel_roundTrip() throws {
        for channel in DiscountChannel.allCases {
            let data = try JSONEncoder().encode(channel)
            let decoded = try JSONDecoder().decode(DiscountChannel.self, from: data)
            XCTAssertEqual(channel, decoded, "DiscountChannel.\(channel) failed round-trip")
        }
    }

    func test_discountChannel_displayName_nonempty() {
        DiscountChannel.allCases.forEach { channel in
            XCTAssertFalse(channel.displayName.isEmpty, "displayName empty for \(channel)")
        }
    }

    // MARK: - DiscountStackOrder

    func test_discountStackOrder_roundTrip() throws {
        for order in DiscountStackOrder.allCases {
            let data = try JSONEncoder().encode(order)
            let decoded = try JSONDecoder().decode(DiscountStackOrder.self, from: data)
            XCTAssertEqual(order, decoded, "DiscountStackOrder.\(order) failed round-trip")
        }
    }

    // MARK: - DiscountRule new fields — Codable round-trip

    func test_discountRule_newFields_encodeDecodeRoundTrip() throws {
        let rule = DiscountRule(
            id: "r1",
            name: "Employee 15%",
            scope: .whole,
            discountPercent: 0.15,
            firstTimeCustomerOnly: false,
            requiredLoyaltyTier: "Gold",
            requiredEmployeeRole: "technician",
            excludedCategories: ["accessories", "parts"],
            channel: .inStoreOnly
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(rule)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiscountRule.self, from: data)

        XCTAssertEqual(decoded.id,                    rule.id)
        XCTAssertEqual(decoded.requiredLoyaltyTier,   "Gold")
        XCTAssertEqual(decoded.requiredEmployeeRole,  "technician")
        XCTAssertEqual(decoded.excludedCategories,    ["accessories", "parts"])
        XCTAssertEqual(decoded.channel,               .inStoreOnly)
        XCTAssertFalse(decoded.firstTimeCustomerOnly)
    }

    func test_discountRule_backwardCompatible_defaults() throws {
        // Simulate a payload that doesn't include the new fields.
        let json = """
        {"id":"r2","name":"10% off","scope":"whole","discount_percent":0.10,"stackable":true,"manager_approval_required":false}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DiscountRule.self, from: json)

        XCTAssertFalse(decoded.firstTimeCustomerOnly)
        XCTAssertNil(decoded.requiredLoyaltyTier)
        XCTAssertNil(decoded.requiredEmployeeRole)
        XCTAssertTrue(decoded.excludedCategories.isEmpty)
        XCTAssertEqual(decoded.channel, .any)
    }

    // MARK: - DiscountEngine — new eligibility gates

    func test_engine_skipsRule_firstTimeCustomer_whenNotFirstTime() async {
        let rule = DiscountRule(
            id: "r1",
            name: "First-time 20%",
            scope: .whole,
            discountPercent: 0.20,
            firstTimeCustomerOnly: true
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 1000)],
            subtotalCents: 1000
        )
        let ctx = DiscountContext(isFirstTimeCustomer: false)
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 0, "Rule should not fire for returning customer")
    }

    func test_engine_appliesRule_firstTimeCustomer_whenFirstTime() async {
        let rule = DiscountRule(
            id: "r1",
            name: "First-time 20%",
            scope: .whole,
            discountPercent: 0.20,
            firstTimeCustomerOnly: true
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 1000)],
            subtotalCents: 1000
        )
        let ctx = DiscountContext(isFirstTimeCustomer: true)
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 200)
    }

    func test_engine_skipsRule_loyaltyTier_mismatch() async {
        let rule = DiscountRule(
            id: "r1",
            name: "Gold 10%",
            scope: .whole,
            discountPercent: 0.10,
            requiredLoyaltyTier: "Gold"
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 500)],
            subtotalCents: 500
        )
        let ctx = DiscountContext(customerLoyaltyTier: "Silver")
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_engine_appliesRule_loyaltyTier_match() async {
        let rule = DiscountRule(
            id: "r1",
            name: "Gold 10%",
            scope: .whole,
            discountPercent: 0.10,
            requiredLoyaltyTier: "Gold"
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 500)],
            subtotalCents: 500
        )
        let ctx = DiscountContext(customerLoyaltyTier: "Gold")
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 50)
    }

    func test_engine_skipsRule_employeeRole_mismatch() async {
        let rule = DiscountRule(
            id: "r1",
            name: "Tech 15%",
            scope: .whole,
            discountPercent: 0.15,
            requiredEmployeeRole: "technician"
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 1000)],
            subtotalCents: 1000
        )
        let ctx = DiscountContext(cashierRole: "sales")
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_engine_skipsLine_excludedCategory() async {
        let itemId = UUID()
        let rule = DiscountRule(
            id: "r1",
            name: "10% off all except accessories",
            scope: .lineItem,
            discountPercent: 0.10,
            excludedCategories: ["accessories"]
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: itemId, sku: nil, category: "accessories", quantity: 1, lineSubtotalCents: 500)],
            subtotalCents: 500
        )
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule])
        XCTAssertEqual(result.totalDiscountCents, 0, "Excluded category should not receive discount")
    }

    func test_engine_appliesLine_nonExcludedCategory() async {
        let itemId = UUID()
        let rule = DiscountRule(
            id: "r1",
            name: "10% off all except accessories",
            scope: .lineItem,
            discountPercent: 0.10,
            excludedCategories: ["accessories"]
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: itemId, sku: nil, category: "parts", quantity: 1, lineSubtotalCents: 500)],
            subtotalCents: 500
        )
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule])
        XCTAssertEqual(result.totalDiscountCents, 50)
    }

    func test_engine_channelRestriction_inStoreOnly_blocked_forOnline() async {
        let rule = DiscountRule(
            id: "r1",
            name: "In-store 10%",
            scope: .whole,
            discountPercent: 0.10,
            channel: .inStoreOnly
        )
        let cart = DiscountCartSnapshot(
            items: [CartItemSnapshot(id: UUID(), sku: nil, category: nil, quantity: 1, lineSubtotalCents: 1000)],
            subtotalCents: 1000
        )
        let ctx = DiscountContext(channel: .onlineOnly)
        let engine = DiscountEngine()
        let result = await engine.apply(cart: cart, rules: [rule], context: ctx)
        XCTAssertEqual(result.totalDiscountCents, 0)
    }
}
