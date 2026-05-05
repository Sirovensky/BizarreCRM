import XCTest
@testable import Pos

/// Tests for `PricingEngine.apply(cart:rules:)`.
/// Covers: BOGO, tiered volume, bulk bundle, segment price, expiry, combined.
final class PricingEngineTests: XCTestCase {

    private let engine = PricingEngine()

    // MARK: - Helpers

    private func item(id: UUID = UUID(), sku: String? = nil, category: String? = nil,
                      quantity: Int = 1, subtotalCents: Int = 1000) -> CartItemSnapshot {
        CartItemSnapshot(id: id, sku: sku, category: category,
                         quantity: quantity, lineSubtotalCents: subtotalCents)
    }

    private func cart(items: [CartItemSnapshot]) -> DiscountCartSnapshot {
        DiscountCartSnapshot(items: items, subtotalCents: items.reduce(0) { $0 + $1.lineSubtotalCents })
    }

    // MARK: - BOGO

    func test_bogo_buyOneGetOne_halfQuantityFree() async {
        // 2 items at 500¢ each = 1000¢ total; BOGO 1+1 → 1 free = 500¢ saving
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 2, subtotalCents: 1_000)])
        let bogoRule = PricingRule(id: "bogo1", name: "BOGO Widget", type: .bogo,
                                   triggerQuantity: 1, freeQuantity: 1, enabled: true)
        let result = await engine.apply(cart: c, rules: [bogoRule])
        XCTAssertEqual(result.totalSavingCents, 500)
        let adj = result.adjustments[id]?.first
        XCTAssertNotNil(adj)
        XCTAssertEqual(adj?.type, .bogo)
        XCTAssertEqual(adj?.freeUnitsCents, 500)
    }

    func test_bogo_notEnoughQuantity_noSaving() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 1, subtotalCents: 500)])
        let bogoRule = PricingRule(id: "bogo2", name: "BOGO", type: .bogo,
                                   triggerQuantity: 1, freeQuantity: 1, enabled: true)
        let result = await engine.apply(cart: c, rules: [bogoRule])
        // 1 item → trigger=1, free=1, cycle=2; 1 < 2 → no complete cycle
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    func test_bogo_buy2Get1_sixItems() async {
        // Buy 2 get 1 free. 6 items at 100¢ each = 600¢. Cycles = 6/3 = 2. Free = 2*1 = 2 items = 200¢
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 6, subtotalCents: 600)])
        let rule = PricingRule(id: "b2g1", name: "Buy 2 Get 1", type: .bogo,
                               triggerQuantity: 2, freeQuantity: 1, enabled: true)
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 200)
    }

    // MARK: - Tiered volume

    func test_tieredVolume_appliesCorrectTier() async {
        // 5 items at 1000¢ each = 5000¢. Tier 5-9 = 800¢/unit → new total 4000¢ → saving 1000¢
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 5, subtotalCents: 5_000)])
        let rule = PricingRule(
            id: "tv1",
            name: "Volume",
            type: .tieredVolume,
            tiers: [
                PricingTier(minQty: 1, maxQty: 4, unitPriceCents: 1_000),
                PricingTier(minQty: 5, maxQty: 9, unitPriceCents: 800),
                PricingTier(minQty: 10, maxQty: nil, unitPriceCents: 600)
            ],
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 1_000)
        XCTAssertEqual(result.adjustments[id]?.first?.newUnitPriceCents, 800)
    }

    func test_tieredVolume_qty1_lowestTier() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 1, subtotalCents: 1_000)])
        let rule = PricingRule(
            id: "tv2",
            name: "Volume",
            type: .tieredVolume,
            tiers: [
                PricingTier(minQty: 1, maxQty: 4, unitPriceCents: 1_000),  // same price → no saving
                PricingTier(minQty: 5, maxQty: nil, unitPriceCents: 800)
            ],
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule])
        // Unit price unchanged → saving = 0
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    func test_tieredVolume_noMatchingTier_noSaving() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 1, subtotalCents: 1_000)])
        let rule = PricingRule(
            id: "tv3",
            name: "High Volume",
            type: .tieredVolume,
            tiers: [PricingTier(minQty: 10, maxQty: nil, unitPriceCents: 500)],
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    // MARK: - Bulk bundle

    func test_bulkBundle_3For1000_4ItemsSaving() async {
        // 4 items at 400¢ each = 1600¢. Bundle: 3 for 1000¢ (333¢/unit).
        // 1 complete bundle of 3 → 333*3=999¢. Remainder 1 → 400¢. Total 1399¢. Saving 201¢.
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 4, subtotalCents: 1_600)])
        let rule = PricingRule(
            id: "bb1",
            name: "3 for $10",
            type: .bulkBundle,
            bundleQuantity: 3,
            bundlePriceCents: 1_000,
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertGreaterThan(result.totalSavingCents, 0)
    }

    func test_bulkBundle_notEnoughItems_noDiscount() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 2, subtotalCents: 800)])
        let rule = PricingRule(id: "bb2", name: "3-for-bundle", type: .bulkBundle,
                               bundleQuantity: 3, bundlePriceCents: 900, enabled: true)
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    // MARK: - Segment pricing

    func test_segmentPrice_matchingSegment_appliedDiscount() async {
        let id = UUID()
        let c = cart(items: [item(id: id, subtotalCents: 10_000)])
        let rule = PricingRule(
            id: "seg1",
            name: "Wholesale 15%",
            type: .segmentPrice,
            targetSegment: "wholesale",
            segmentDiscountPercent: 0.15,
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule], customerSegment: "wholesale")
        XCTAssertEqual(result.totalSavingCents, 1_500)
    }

    func test_segmentPrice_nonMatchingSegment_noDiscount() async {
        let id = UUID()
        let c = cart(items: [item(id: id, subtotalCents: 10_000)])
        let rule = PricingRule(
            id: "seg2",
            name: "Wholesale 15%",
            type: .segmentPrice,
            targetSegment: "wholesale",
            segmentDiscountPercent: 0.15,
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule], customerSegment: "retail")
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    func test_segmentPrice_noSegment_noDiscount() async {
        let id = UUID()
        let c = cart(items: [item(id: id, subtotalCents: 10_000)])
        let rule = PricingRule(
            id: "seg3",
            name: "Wholesale",
            type: .segmentPrice,
            targetSegment: "wholesale",
            segmentDiscountPercent: 0.15,
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule], customerSegment: nil)
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    // MARK: - SKU targeting

    func test_skuTargeted_onlyMatchingSku_discounted() async {
        let matchId = UUID()
        let otherID = UUID()
        let c = DiscountCartSnapshot(items: [
            CartItemSnapshot(id: matchId, sku: "SKU-A", category: nil, quantity: 2, lineSubtotalCents: 2_000),
            CartItemSnapshot(id: otherID, sku: "SKU-B", category: nil, quantity: 1, lineSubtotalCents: 1_000)
        ], subtotalCents: 3_000)
        let rule = PricingRule(id: "tv-sku", name: "Tiered SKU-A", type: .tieredVolume,
                               targetSku: "SKU-A",
                               tiers: [
                                   PricingTier(minQty: 2, maxQty: nil, unitPriceCents: 800)
                               ],
                               enabled: true)
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertNotNil(result.adjustments[matchId])
        XCTAssertNil(result.adjustments[otherID])
    }

    // MARK: - Expiry

    func test_expiredRule_notApplied() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 2, subtotalCents: 1_000)])
        let rule = PricingRule(
            id: "exp1",
            name: "BOGO",
            type: .bogo,
            triggerQuantity: 1,
            freeQuantity: 1,
            validTo: Date(timeIntervalSinceNow: -86_400),
            enabled: true
        )
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    func test_disabledRule_notApplied() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 2, subtotalCents: 1_000)])
        let rule = PricingRule(
            id: "dis1",
            name: "BOGO",
            type: .bogo,
            triggerQuantity: 1,
            freeQuantity: 1,
            enabled: false
        )
        let result = await engine.apply(cart: c, rules: [rule])
        XCTAssertEqual(result.totalSavingCents, 0)
    }

    // MARK: - Cart.applyPricingResult integration

    @MainActor
    func test_cart_applyPricingResult_setsFields() async {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", quantity: 2, unitPrice: 50))
        let adj = PricingAdjustment(ruleId: "bogo1", ruleName: "BOGO", type: .bogo,
                                    freeUnitsCents: 2500, savingCents: 2500)
        let itemId = cart.items.first!.id
        let result = PricingResult(adjustments: [itemId: [adj]], totalSavingCents: 2500)
        cart.applyPricingResult(result)
        XCTAssertEqual(cart.pricingSavingCents, 2_500)
        XCTAssertNotNil(cart.pricingAdjustments[itemId])
    }

    // MARK: - PricingTier matches helper

    func test_pricingTier_matches() {
        let tier = PricingTier(minQty: 5, maxQty: 9, unitPriceCents: 800)
        XCTAssertFalse(tier.matches(qty: 4))
        XCTAssertTrue(tier.matches(qty: 5))
        XCTAssertTrue(tier.matches(qty: 9))
        XCTAssertFalse(tier.matches(qty: 10))
    }

    func test_pricingTier_openEnded_matchesAboveMin() {
        let tier = PricingTier(minQty: 10, maxQty: nil, unitPriceCents: 600)
        XCTAssertFalse(tier.matches(qty: 9))
        XCTAssertTrue(tier.matches(qty: 10))
        XCTAssertTrue(tier.matches(qty: 999))
    }
}
