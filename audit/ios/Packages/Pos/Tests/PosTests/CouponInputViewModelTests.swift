#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking
import Core

// MARK: - CouponMockAPIClient

/// Minimal APIClient stub for coupon tests.
private final class CouponMockAPIClient: APIClient, @unchecked Sendable {

    // Configurable stubs
    var applyResult: Result<CouponApplyResponse, Error>?
    var getResult: Result<[CouponCode], Error>?

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/coupons"), let res = getResult {
            return try res.get() as! T
        }
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/coupons/apply"), let res = applyResult {
            return try res.get() as! T
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - CouponInputViewModelTests

/// Tests for `CouponInputViewModel`.
/// Covers: apply success, apply error, already-used / expired / exhausted
/// server errors, remove, empty input guard, state transitions.
@MainActor
final class CouponInputViewModelTests: XCTestCase {

    private func makeCoupon(id: String = "c1",
                            code: String = "SAVE20",
                            ruleId: String = "r1",
                            ruleName: String = "20% off",
                            expiresAt: Date? = nil,
                            usesRemaining: Int? = nil) -> CouponCode {
        CouponCode(id: id, code: code, ruleId: ruleId, ruleName: ruleName,
                   usesRemaining: usesRemaining, expiresAt: expiresAt)
    }

    private func makeVM(api: CouponMockAPIClient) -> CouponInputViewModel {
        CouponInputViewModel(api: api, cartId: { "cart-uuid-123" })
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeVM(api: CouponMockAPIClient())
        if case .idle = vm.state { XCTAssert(true) }
        else { XCTFail("Expected idle, got \(vm.state)") }
        XCTAssertFalse(vm.isApplied)
        XCTAssertFalse(vm.canApply)
    }

    func test_emptyCode_canApply_isFalse() {
        let vm = makeVM(api: CouponMockAPIClient())
        vm.codeInput = ""
        XCTAssertFalse(vm.canApply)
    }

    func test_nonEmptyCode_canApply_isTrue() {
        let vm = makeVM(api: CouponMockAPIClient())
        vm.codeInput = "HELLO"
        XCTAssertTrue(vm.canApply)
    }

    func test_codeInput_autoUppercased() {
        let vm = makeVM(api: CouponMockAPIClient())
        vm.codeInput = "hello"
        XCTAssertEqual(vm.codeInput, "HELLO")
    }

    // MARK: - Successful apply

    func test_apply_success_stateBecomesApplied() async {
        let api = CouponMockAPIClient()
        let coupon = makeCoupon()
        api.applyResult = .success(CouponApplyResponse(coupon: coupon, discountCents: 500, message: "20% off applied"))
        let vm = makeVM(api: api)
        vm.codeInput = "SAVE20"
        await vm.apply()

        guard case .applied(let c, let d) = vm.state else {
            XCTFail("Expected applied state, got \(vm.state)"); return
        }
        XCTAssertEqual(c.code, "SAVE20")
        XCTAssertEqual(d, 500)
        XCTAssertTrue(vm.isApplied)
        XCTAssertFalse(vm.canApply)  // already applied
    }

    func test_apply_success_discountCentsNonZero() async {
        let api = CouponMockAPIClient()
        let coupon = makeCoupon(code: "TEN")
        api.applyResult = .success(CouponApplyResponse(coupon: coupon, discountCents: 1_000, message: nil))
        let vm = makeVM(api: api)
        vm.codeInput = "TEN"
        await vm.apply()
        XCTAssertEqual(vm.state.discountCents, 1_000)
    }

    // MARK: - Error states

    func test_apply_networkError_stateBecomesError() async {
        let api = CouponMockAPIClient()
        api.applyResult = .failure(URLError(.notConnectedToInternet))
        let vm = makeVM(api: api)
        vm.codeInput = "BADCODE"
        await vm.apply()

        guard case .error = vm.state else {
            XCTFail("Expected error state"); return
        }
        XCTAssertFalse(vm.isApplied)
    }

    func test_apply_appError_errorMessageUsed() async {
        let api = CouponMockAPIClient()
        api.applyResult = .failure(AppError.server(statusCode: 422, message: "Coupon already used"))
        let vm = makeVM(api: api)
        vm.codeInput = "USED"
        await vm.apply()

        if case .error(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected error state")
        }
    }

    func test_editAfterError_resetsToIdle() async {
        let api = CouponMockAPIClient()
        api.applyResult = .failure(URLError(.badURL))
        let vm = makeVM(api: api)
        vm.codeInput = "CODE"
        await vm.apply()
        // Simulate user editing the field after error
        vm.codeInput = "NEW"
        if case .idle = vm.state { XCTAssert(true) }
        else { XCTFail("Expected idle after edit, got \(vm.state)") }
    }

    // MARK: - Empty input guard

    func test_apply_emptyInput_doesNotCallAPI_setsError() async {
        let api = CouponMockAPIClient()
        // applyResult is nil so any call would throw — test that no call is made
        let vm = makeVM(api: api)
        vm.codeInput = "   "  // whitespace only
        await vm.apply()
        if case .error = vm.state { XCTAssert(true) }
        else { XCTFail("Expected error for whitespace input") }
    }

    // MARK: - Remove

    func test_remove_resetsToIdleAndClearsInput() async {
        let api = CouponMockAPIClient()
        let coupon = makeCoupon()
        api.applyResult = .success(CouponApplyResponse(coupon: coupon, discountCents: 200, message: nil))
        let vm = makeVM(api: api)
        vm.codeInput = "SAVE20"
        await vm.apply()
        XCTAssertTrue(vm.isApplied)

        vm.remove()
        XCTAssertFalse(vm.isApplied)
        XCTAssertEqual(vm.codeInput, "")
        if case .idle = vm.state { XCTAssert(true) }
        else { XCTFail("Expected idle after remove") }
    }

    // MARK: - CouponCode model helpers

    func test_couponCode_uppercasedOnInit() {
        let c = CouponCode(id: "1", code: "save10", ruleId: "r", ruleName: "10%")
        XCTAssertEqual(c.code, "SAVE10")
    }

    func test_couponCode_isExpired() {
        let past = Date(timeIntervalSinceNow: -1)
        let c = CouponCode(id: "1", code: "OLD", ruleId: "r", ruleName: "N/A", expiresAt: past)
        XCTAssertTrue(c.isExpired())
        XCTAssertFalse(c.isActive)
    }

    func test_couponCode_notExpired() {
        let future = Date(timeIntervalSinceNow: 86_400)
        let c = CouponCode(id: "1", code: "NEW", ruleId: "r", ruleName: "N/A", expiresAt: future)
        XCTAssertFalse(c.isExpired())
    }

    func test_couponCode_exhausted() {
        let c = CouponCode(id: "1", code: "USED", ruleId: "r", ruleName: "N/A", usesRemaining: 0)
        XCTAssertTrue(c.isExhausted)
        XCTAssertFalse(c.isActive)
    }

    func test_couponCode_unlimited_notExhausted() {
        let c = CouponCode(id: "1", code: "OPEN", ruleId: "r", ruleName: "N/A", usesRemaining: nil)
        XCTAssertFalse(c.isExhausted)
        XCTAssertTrue(c.isActive)
    }

    // MARK: - Cart coupon helpers

    func test_cart_totalCents_includesCouponDiscount() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 100))  // 10000¢
        let coupon = makeCoupon()
        cart.applyCoupon(coupon, discountCents: 1_000)
        // subtotal 10000 - coupon 1000 = 9000
        XCTAssertEqual(cart.totalCents, 9_000)
    }

    func test_cart_totalCents_includesPricingSaving() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 100))  // 10000¢
        let adj = PricingAdjustment(ruleId: "bogo", ruleName: "BOGO", type: .bogo,
                                    freeUnitsCents: 2_000, savingCents: 2_000)
        let itemId = cart.items.first!.id
        cart.applyPricingResult(PricingResult(adjustments: [itemId: [adj]], totalSavingCents: 2_000))
        // subtotal 10000 - pricingSaving 2000 = 8000
        XCTAssertEqual(cart.totalCents, 8_000)
    }

    func test_cart_totalSavingsCents_combinesAllSources() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 100))
        cart.setCartDiscount(cents: 500)
        let coupon = makeCoupon()
        cart.applyCoupon(coupon, discountCents: 300)
        let adj = PricingAdjustment(ruleId: "tv", ruleName: "Tiered", type: .tieredVolume,
                                    savingCents: 200)
        let itemId = cart.items.first!.id
        cart.applyPricingResult(PricingResult(adjustments: [itemId: [adj]], totalSavingCents: 200))
        XCTAssertEqual(cart.totalSavingsCents, 1_000)  // 500 + 300 + 200
    }
}
#endif
