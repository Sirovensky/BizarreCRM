import XCTest
@testable import Pos

/// §16.15 — Unit tests for member discount auto-apply and hasMemberAttached.
@MainActor
final class MemberDiscountTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(loyaltyPoints: Int? = nil) -> PosViewModel {
        let vm = PosViewModel()
        if let pts = loyaltyPoints {
            // Simulate loaded customer context with loyalty balance
            // (We call the internal test-only setter if available; otherwise use
            // loadCustomerContext which requires an API — here we bypass it.)
            // PosViewModel initializer sets customerContext to .empty,
            // so we indirectly inject via the public test path.
            _ = vm   // just ensures we hit the @MainActor init
        }
        return vm
    }

    private func makeCart(subtotalCents: Int = 10000) -> Cart {
        let cart = Cart()
        // Add a line worth `subtotalCents` (roughly)
        let item = CartItem(
            name: "Widget",
            sku: "SKU-001",
            quantity: 1,
            unitPrice: Decimal(subtotalCents) / 100
        )
        cart.add(item)
        return cart
    }

    // MARK: - applyMemberDiscountIfNeeded

    func test_applyMemberDiscount_zeroPct_doesNothing() {
        let vm = PosViewModel()
        let cart = makeCart()
        let result = vm.applyMemberDiscountIfNeeded(to: cart, discountPercent: 0)
        XCTAssertNil(result)
        XCTAssertNil(cart.cartDiscountPercent)
    }

    func test_applyMemberDiscount_10pct_appliesCorrectFraction() {
        let vm = PosViewModel()
        let cart = makeCart()
        let result = vm.applyMemberDiscountIfNeeded(to: cart, discountPercent: 10)
        XCTAssertEqual(result, 0.10, accuracy: 0.001)
        XCTAssertEqual(cart.cartDiscountPercent ?? 0, 0.10, accuracy: 0.001)
    }

    func test_applyMemberDiscount_doesNotOverrideHigherExistingDiscount() {
        let vm = PosViewModel()
        let cart = makeCart()
        // Pre-set a larger manager discount (20%)
        cart.setCartDiscountPercent(0.20)
        // Member discount = 10% → should not override
        let result = vm.applyMemberDiscountIfNeeded(to: cart, discountPercent: 10)
        // Returns existing (20%)
        XCTAssertEqual(result ?? 0, 0.20, accuracy: 0.001)
        XCTAssertEqual(cart.cartDiscountPercent ?? 0, 0.20, accuracy: 0.001)
    }

    func test_applyMemberDiscount_overridesLowerExistingDiscount() {
        let vm = PosViewModel()
        let cart = makeCart()
        // Pre-set a smaller discount (5%)
        cart.setCartDiscountPercent(0.05)
        // Member discount = 15% → should upgrade
        let result = vm.applyMemberDiscountIfNeeded(to: cart, discountPercent: 15)
        XCTAssertEqual(result ?? 0, 0.15, accuracy: 0.001)
        XCTAssertEqual(cart.cartDiscountPercent ?? 0, 0.15, accuracy: 0.001)
    }

    // MARK: - hasMemberAttached

    func test_hasMemberAttached_falseWhenContextIsEmpty() {
        let vm = PosViewModel()
        // Fresh VM has .empty context
        XCTAssertFalse(vm.hasMemberAttached)
    }

    // MARK: - CashPeriodLock model

    func test_cashPeriodLockRequest_encodesCorrectKeys() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 3600)
        let req = CashPeriodLockRequest(
            periodStart: start,
            periodEnd: end,
            reconciledRevenueCents: 50000,
            notes: "Month closed"
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["period_start"])
        XCTAssertNotNil(json?["period_end"])
        XCTAssertEqual(json?["reconciled_revenue_cents"] as? Int, 50000)
        XCTAssertEqual(json?["notes"] as? String, "Month closed")
    }
}
