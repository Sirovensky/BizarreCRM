import XCTest
@testable import Pos

final class GiftReceiptGeneratorTests: XCTestCase {

    // MARK: - Test fixture

    private func makeSale(lines: [SaleLineRecord]? = nil) -> SaleRecord {
        SaleRecord(
            id: 42,
            receiptNumber: "R-20240420-0042",
            date: Date(timeIntervalSince1970: 0),
            customerName: "Alice Smith",
            customerPhone: "+12125551234",
            lines: lines ?? [
                SaleLineRecord(id: 1, name: "Screen Repair", sku: "SKU-001", quantity: 1,
                               unitPriceCents: 12999, discountCents: 0, lineTotalCents: 12999),
                SaleLineRecord(id: 2, name: "Screen Protector", sku: "SKU-002", quantity: 2,
                               unitPriceCents: 1499, discountCents: 0, lineTotalCents: 2998),
            ],
            subtotalCents: 15997,
            discountCents: 500,
            taxCents: 1200,
            tipCents: 300,
            feesCents: 0,
            totalCents: 16997,
            tenders: [
                SaleTenderRecord(id: 1, method: "Visa", amountCents: 16997, last4: "4242")
            ],
            currencyCode: "USD"
        )
    }

    // MARK: - Price stripping

    func test_allMoneyFieldsAreZero() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())

        XCTAssertEqual(payload.subtotalCents, 0, "subtotal must be stripped")
        XCTAssertEqual(payload.discountCents, 0, "discount must be stripped")
        XCTAssertEqual(payload.taxCents,      0, "tax must be stripped")
        XCTAssertEqual(payload.tipCents,      0, "tip must be stripped")
        XCTAssertEqual(payload.feesCents,     0, "fees must be stripped")
        XCTAssertEqual(payload.totalCents,    0, "total must be stripped")
    }

    func test_lineMoneyFieldsAreZero() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())

        for line in payload.lines {
            XCTAssertEqual(line.unitPriceCents,  0, "unit price must be stripped on \(line.name)")
            XCTAssertEqual(line.discountCents,   0, "line discount must be stripped on \(line.name)")
            XCTAssertEqual(line.lineTotalCents,  0, "line total must be stripped on \(line.name)")
        }
    }

    func test_tendersAreStripped() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertTrue(payload.tenders.isEmpty, "payment method must be stripped")
    }

    func test_customerNameIsStripped() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertNil(payload.customerName, "customer name must be stripped")
    }

    // MARK: - Non-sensitive fields preserved

    func test_itemNamesPreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        let names = payload.lines.map(\.name)
        XCTAssertTrue(names.contains("Screen Repair"))
        XCTAssertTrue(names.contains("Screen Protector"))
    }

    func test_skusPreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        let skus = payload.lines.compactMap(\.sku)
        XCTAssertTrue(skus.contains("SKU-001"), "SKU needed for returns processing")
        XCTAssertTrue(skus.contains("SKU-002"))
    }

    func test_quantitiesPreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertEqual(payload.lines[0].quantity, 1)
        XCTAssertEqual(payload.lines[1].quantity, 2)
    }

    func test_orderNumberPreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertEqual(payload.orderNumber, "R-20240420-0042")
    }

    func test_datePreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertEqual(payload.date, Date(timeIntervalSince1970: 0))
    }

    func test_currencyCodePreserved() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertEqual(payload.currencyCode, "USD")
    }

    // MARK: - Header override

    func test_merchantNameIsGiftReceiptHeader() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertEqual(payload.merchant.name, "GIFT RECEIPT")
    }

    // MARK: - Footer

    func test_footerContainsReturnPolicy() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertNotNil(payload.footer)
        XCTAssertTrue(payload.footer!.contains("returned"), "footer should mention return policy")
    }

    func test_footerMentionsPriceHiding() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        XCTAssertTrue(payload.footer!.lowercased().contains("price"), "footer should explain price omission")
    }

    // MARK: - Empty cart edge case

    func test_emptyLinesProducesEmptyGiftLines() {
        let sale = makeSale(lines: [])
        let payload = GiftReceiptGenerator.buildPayload(sale: sale)
        XCTAssertTrue(payload.lines.isEmpty)
        XCTAssertEqual(payload.totalCents, 0)
    }

    // MARK: - Text renderer integration

    func test_renderedTextDoesNotContainDollarAmounts() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        let text = PosReceiptRenderer.text(payload)

        // All monetary outputs for the sale items should be $0.00
        // but the renderer won't print $0.00 for totals since they're
        // hidden — verify that total line amounts ≥ $1 are absent.
        XCTAssertFalse(text.contains("$129.99"), "unit price must not appear")
        XCTAssertFalse(text.contains("$169.97"), "total must not appear")
        XCTAssertFalse(text.contains("Visa"),    "payment method must not appear")
    }

    func test_renderedTextContainsItemNames() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        let text = PosReceiptRenderer.text(payload)
        XCTAssertTrue(text.contains("Screen Repair"))
        XCTAssertTrue(text.contains("Screen Protector"))
    }

    func test_renderedTextContainsReceiptHeader() {
        let payload = GiftReceiptGenerator.buildPayload(sale: makeSale())
        let text = PosReceiptRenderer.text(payload)
        XCTAssertTrue(text.contains("GIFT RECEIPT"))
    }
}
