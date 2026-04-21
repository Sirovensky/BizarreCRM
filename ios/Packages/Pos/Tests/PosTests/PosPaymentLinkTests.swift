import XCTest
@testable import Pos
import Networking

@MainActor
final class PosPaymentLinkTests: XCTestCase {

    // MARK: - URL builder

    /// `makePaymentLinkURL` strips API paths back to the origin so share
    /// URLs target the public /pay page, not an /api/v1 route.
    func test_makePaymentLinkURL_stripsApiPath() {
        let base = URL(string: "https://shop.example.com/api/v1")!
        XCTAssertEqual(
            makePaymentLinkURL(baseURL: base, token: "abc"),
            "https://shop.example.com/pay/abc"
        )
    }

    func test_makePaymentLinkURL_preservesPort() {
        let base = URL(string: "http://localhost:3000/api/v1")!
        XCTAssertEqual(
            makePaymentLinkURL(baseURL: base, token: "xyz"),
            "http://localhost:3000/pay/xyz"
        )
    }

    func test_makePaymentLinkURL_emptyTokenReturnsEmpty() {
        let base = URL(string: "https://shop.example.com/api/v1")!
        XCTAssertEqual(makePaymentLinkURL(baseURL: base, token: ""), "")
    }

    func test_makePaymentLinkURL_noBaseReturnsRelativePath() {
        XCTAssertEqual(
            makePaymentLinkURL(baseURL: nil, token: "abc"),
            "/pay/abc"
        )
    }

    // MARK: - Request body encoding

    /// Server accepts dollars (Double) on the `amount` key. iOS-side we
    /// store cents and convert at the edge so call sites stay cents-only.
    func test_createRequest_encodesDollarsAndSnakeCase() throws {
        let req = CreatePaymentLinkRequest(
            amountCents: 1999,
            customerId: 42,
            description: "Sale",
            expiresAt: "2026-05-01T00:00:00Z",
            invoiceId: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"amount\":19.99"), "Expected dollars, got: \(json)")
        XCTAssertTrue(json.contains("\"customer_id\":42"))
        XCTAssertTrue(json.contains("\"description\":\"Sale\""))
        XCTAssertTrue(json.contains("\"expires_at\":\"2026-05-01T00:00:00Z\""))
        // `invoice_id` omitted when nil.
        XCTAssertFalse(json.contains("invoice_id"))
    }

    func test_createRequest_zeroCentsEncodesAsZero() throws {
        let req = CreatePaymentLinkRequest(amountCents: 0)
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"amount\":0"))
    }

    // MARK: - Response decoding

    /// Mirrors the DB row: snake-case `amount_cents`, `token`, `paid_at`.
    /// iOS surface exposes `amountCents`, `shortId`, `isPaid`.
    func test_paymentLink_decodesSnakeCase() throws {
        let json = """
        {
          "id": 123,
          "token": "abcdef_01",
          "status": "active",
          "amount_cents": 2500,
          "created_at": "2026-04-20T12:00:00Z",
          "expires_at": "2026-04-27T12:00:00Z",
          "paid_at": null,
          "description": "Invoice from BizarreCRM",
          "customer_id": 7
        }
        """.data(using: .utf8)!
        let link = try JSONDecoder().decode(PaymentLink.self, from: json)
        XCTAssertEqual(link.id, 123)
        XCTAssertEqual(link.shortId, "abcdef_01")
        XCTAssertEqual(link.amountCents, 2500)
        XCTAssertEqual(link.status, "active")
        XCTAssertTrue(link.isActive)
        XCTAssertFalse(link.isPaid)
        XCTAssertEqual(link.statusKind, .active)
        XCTAssertEqual(link.customerId, 7)
    }

    func test_paymentLink_paidStatusDecoded() throws {
        let json = """
        {
          "id": 1,
          "token": "t",
          "status": "paid",
          "amount_cents": 100,
          "paid_at": "2026-04-20T12:05:00Z"
        }
        """.data(using: .utf8)!
        let link = try JSONDecoder().decode(PaymentLink.self, from: json)
        XCTAssertTrue(link.isPaid)
        XCTAssertEqual(link.statusKind, .paid)
        XCTAssertFalse(link.isActive)
    }

    func test_paymentLink_unknownStatusBecomesUnknownKind() throws {
        let json = """
        { "id": 1, "token": "t", "status": "pending", "amount_cents": 100 }
        """.data(using: .utf8)!
        let link = try JSONDecoder().decode(PaymentLink.self, from: json)
        XCTAssertEqual(link.statusKind, .unknown)
    }

    func test_paymentLink_withURL_preservesOtherFields() throws {
        let source = PaymentLink(
            id: 9,
            shortId: "abc",
            url: "",
            status: "active",
            amountCents: 500,
            createdAt: "2026-04-20T12:00:00Z",
            expiresAt: nil,
            paidAt: nil,
            description: "Sale"
        )
        let copy = source.withURL("https://shop.example.com/pay/abc")
        XCTAssertEqual(copy.url, "https://shop.example.com/pay/abc")
        XCTAssertEqual(copy.id, 9)
        XCTAssertEqual(copy.shortId, "abc")
        XCTAssertEqual(copy.amountCents, 500)
        XCTAssertEqual(copy.description, "Sale")
    }

    // MARK: - Cart pending-state integration

    func test_cart_markPendingPaymentLink_disablesChargeFlag() {
        let cart = Cart()
        XCTAssertFalse(cart.hasPendingPaymentLink)
        cart.markPendingPaymentLink(id: 42, token: "tok123")
        XCTAssertTrue(cart.hasPendingPaymentLink)
        XCTAssertEqual(cart.pendingPaymentLinkId, 42)
        XCTAssertEqual(cart.pendingPaymentLinkToken, "tok123")
    }

    func test_cart_clearPendingPaymentLink_removesMarker() {
        let cart = Cart()
        cart.markPendingPaymentLink(id: 42, token: "tok123")
        cart.clearPendingPaymentLink()
        XCTAssertFalse(cart.hasPendingPaymentLink)
        XCTAssertNil(cart.pendingPaymentLinkId)
        XCTAssertNil(cart.pendingPaymentLinkToken)
    }

    func test_cart_clear_alsoDropsPendingLink() {
        let cart = Cart()
        cart.markPendingPaymentLink(id: 1, token: "t")
        cart.add(CartItem(name: "A", unitPrice: 1))
        cart.clear()
        XCTAssertFalse(cart.hasPendingPaymentLink)
        XCTAssertTrue(cart.isEmpty)
    }

    // MARK: - Expiry helper

    /// Default 7-day expiry produces an ISO-8601 timestamp roughly 7 days
    /// ahead. We allow ±30 s slack so a slow CI test host doesn't flake.
    func test_expiryISO_sevenDays_isRoughlyOneWeekAhead() throws {
        let iso = PosPaymentLinkViewModel.expiryISO(daysFromNow: 7)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let parsed = try XCTUnwrap(fmt.date(from: iso))
        let delta = parsed.timeIntervalSinceNow
        XCTAssertGreaterThan(delta, 7 * 86_400 - 30)
        XCTAssertLessThan(delta, 7 * 86_400 + 30)
    }

    func test_expiryISO_clampsToAtLeastOneDay() throws {
        let iso = PosPaymentLinkViewModel.expiryISO(daysFromNow: 0)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let parsed = try XCTUnwrap(fmt.date(from: iso))
        // 0 → clamped to 1 day.
        XCTAssertGreaterThan(parsed.timeIntervalSinceNow, 86_400 - 30)
    }
}
