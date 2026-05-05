import XCTest
@testable import Pos

/// §16.7 — `PosReceiptRenderer` is pure: given a `Payload`, the plain-text
/// and HTML bodies are byte-for-byte deterministic. These tests pin down:
///   - money formatting (cents → localized currency)
///   - HTML escaping of `<`, `>`, `&`, `"`, `'`
///   - total + discount + tax + tip line inclusion
///   - customer + merchant header rendering
final class PosReceiptRendererTests: XCTestCase {

    /// Shared payload fixture. Arbitrary but stable — tests reach in via
    /// `Self.payload(...)` to mutate specific fields per case.
    private static func payload(
        merchant: String = "BizarreCRM",
        lineName: String = "Widget",
        lineSku: String? = "WID-1",
        quantity: Int = 2,
        unitPriceCents: Int = 1099,
        lineTotalCents: Int = 2198,
        subtotalCents: Int = 2198,
        discountCents: Int = 0,
        taxCents: Int = 0,
        tipCents: Int = 0,
        totalCents: Int = 2198,
        tenders: [PosReceiptRenderer.Payload.Tender] = [],
        customerName: String? = nil,
        footer: String? = nil
    ) -> PosReceiptRenderer.Payload {
        PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(name: merchant),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            customerName: customerName,
            orderNumber: nil,
            lines: [
                PosReceiptRenderer.Payload.Line(
                    name: lineName,
                    sku: lineSku,
                    quantity: quantity,
                    unitPriceCents: unitPriceCents,
                    discountCents: 0,
                    lineTotalCents: lineTotalCents
                )
            ],
            subtotalCents: subtotalCents,
            discountCents: discountCents,
            feesCents: 0,
            taxCents: taxCents,
            tipCents: tipCents,
            totalCents: totalCents,
            tenders: tenders,
            currencyCode: "USD",
            footer: footer
        )
    }

    // MARK: - HTML escape

    func test_escapeHTML_escapesAllFiveSpecialChars() {
        let raw = "<script>alert(\"x\" & 'y')</script>"
        let escaped = PosReceiptRenderer.escapeHTML(raw)
        XCTAssertFalse(escaped.contains("<script>"))
        XCTAssertFalse(escaped.contains("\""))
        XCTAssertFalse(escaped.contains("'"))
        XCTAssertTrue(escaped.contains("&lt;"))
        XCTAssertTrue(escaped.contains("&gt;"))
        XCTAssertTrue(escaped.contains("&amp;"))
        XCTAssertTrue(escaped.contains("&quot;"))
        XCTAssertTrue(escaped.contains("&#39;"))
    }

    func test_html_mustEscapeMerchantName() {
        let p = Self.payload(merchant: "<Fish & Chips>")
        let html = PosReceiptRenderer.html(p)
        XCTAssertFalse(html.contains("<Fish & Chips>"))
        XCTAssertTrue(html.contains("&lt;Fish &amp; Chips&gt;"))
    }

    func test_html_mustEscapeLineName() {
        let p = Self.payload(lineName: "Burger & Fries")
        let html = PosReceiptRenderer.html(p)
        XCTAssertFalse(html.contains("Burger & Fries"))
        XCTAssertTrue(html.contains("Burger &amp; Fries"))
    }

    // MARK: - Totals

    func test_text_includesSubtotalDiscountTaxTipTotal() {
        let p = Self.payload(
            subtotalCents: 2000,
            discountCents: 200,
            taxCents: 144,
            tipCents: 300,
            totalCents: 2244
        )
        let text = PosReceiptRenderer.text(p)
        XCTAssertTrue(text.contains("Subtotal"))
        XCTAssertTrue(text.contains("Discount"))
        XCTAssertTrue(text.contains("Tax"))
        XCTAssertTrue(text.contains("Tip"))
        XCTAssertTrue(text.contains("Total"))
    }

    func test_text_skipsDiscountRow_whenDiscountIsZero() {
        let p = Self.payload(discountCents: 0, taxCents: 120, totalCents: 2318)
        let text = PosReceiptRenderer.text(p)
        XCTAssertFalse(text.contains("Discount"))
        XCTAssertTrue(text.contains("Tax"))
    }

    func test_text_skipsTipRow_whenTipIsZero() {
        let text = PosReceiptRenderer.text(Self.payload(tipCents: 0))
        XCTAssertFalse(text.contains("Tip"))
    }

    func test_text_rendersCentsAsLocalizedCurrency() {
        let p = Self.payload(
            unitPriceCents: 199,
            lineTotalCents: 597,
            subtotalCents: 597,
            totalCents: 597
        )
        let text = PosReceiptRenderer.text(p)
        // `$5.97` regardless of locale — en_US_POSIX formatter bakes this.
        XCTAssertTrue(text.contains("$5.97"))
    }

    // MARK: - Tenders

    func test_text_listsTenders_whenProvided() {
        let p = Self.payload(
            tenders: [
                PosReceiptRenderer.Payload.Tender(method: "Card", amountCents: 1000, last4: "4242"),
                PosReceiptRenderer.Payload.Tender(method: "Cash", amountCents: 1198)
            ]
        )
        let text = PosReceiptRenderer.text(p)
        XCTAssertTrue(text.contains("Card"))
        XCTAssertTrue(text.contains("•4242"))
        XCTAssertTrue(text.contains("Cash"))
    }

    func test_html_showsTotalRowAsEmphasized() {
        let p = Self.payload(totalCents: 1999)
        let html = PosReceiptRenderer.html(p)
        XCTAssertTrue(html.contains("font-weight:700"))
    }

    // MARK: - Headers

    func test_text_showsCustomerWhenProvided() {
        let p = Self.payload(customerName: "Ada Lovelace")
        let text = PosReceiptRenderer.text(p)
        XCTAssertTrue(text.contains("Customer: Ada Lovelace"))
    }

    func test_text_omitsCustomer_whenNil() {
        let text = PosReceiptRenderer.text(Self.payload(customerName: nil))
        XCTAssertFalse(text.contains("Customer:"))
    }

    func test_html_includesHtmlPrologue() {
        let html = PosReceiptRenderer.html(Self.payload())
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<html>"))
        XCTAssertTrue(html.contains("</html>"))
    }

    // MARK: - Footer

    func test_text_appendsFooter() {
        let p = Self.payload(footer: "Thanks for shopping!")
        let text = PosReceiptRenderer.text(p)
        XCTAssertTrue(text.hasSuffix("Thanks for shopping!"))
    }

    // MARK: - Deterministic date

    func test_text_rendersDateInStableFormat() {
        let text = PosReceiptRenderer.text(Self.payload())
        // Fixed epoch 1_700_000_000 = 2023-11-14 22:13 UTC
        XCTAssertTrue(text.contains("2023-11-14 22:13"))
    }
}
