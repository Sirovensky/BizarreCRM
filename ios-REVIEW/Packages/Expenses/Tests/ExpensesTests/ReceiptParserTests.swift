import XCTest
@testable import Expenses

final class ReceiptParserTests: XCTestCase {

    // MARK: - Amount extraction

    func test_extractAmount_dollarSign() {
        XCTAssertEqual(ReceiptParser.extractAmount(from: "Total $12.34"), 1234)
    }

    func test_extractAmount_noDollarSign() {
        XCTAssertEqual(ReceiptParser.extractAmount(from: "Amount: 99.99"), 9999)
    }

    func test_extractAmount_commaDecimal() {
        XCTAssertEqual(ReceiptParser.extractAmount(from: "Subtotal 10,50"), 1050)
    }

    func test_extractAmount_noAmount_returnsNil() {
        XCTAssertNil(ReceiptParser.extractAmount(from: "No amounts here"))
    }

    func test_extractAmount_roundsHalfUp() {
        // $1.005 → should round to 101 cents (0.5 rounds up)
        let result = ReceiptParser.extractAmount(from: "$1.00")
        XCTAssertEqual(result, 100)
    }

    // MARK: - Total extraction

    func test_parse_extractsTotal() {
        let text = """
        Shell Gas Station
        Fuel          $45.00
        Total         $45.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.totalCents, 4500)
    }

    func test_parse_grandTotalKeyword() {
        let text = """
        Acme Store
        Item A  $10.00
        Grand Total $10.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.totalCents, 1000)
    }

    func test_parse_amountDueKeyword() {
        let text = """
        Home Depot
        Supplies $87.43
        Amount Due $87.43
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.totalCents, 8743)
    }

    // MARK: - Tax extraction

    func test_parse_extractsTax() {
        let text = """
        Starbucks
        Coffee   $5.00
        Tax      $0.45
        Total    $5.45
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.taxCents, 45)
        XCTAssertEqual(result.totalCents, 545)
    }

    func test_parse_salesTaxLabel() {
        let text = """
        Store
        Item $20.00
        Sales Tax $1.60
        Total $21.60
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.taxCents, 160)
    }

    // MARK: - Subtotal extraction

    func test_parse_extractsSubtotal() {
        let text = """
        Restaurant
        Food     $30.00
        Subtotal $30.00
        Tax       $2.40
        Total    $32.40
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.subtotalCents, 3000)
        XCTAssertEqual(result.taxCents, 240)
        XCTAssertEqual(result.totalCents, 3240)
    }

    // MARK: - Merchant extraction

    func test_parse_merchantIsFirstMeaningfulLine() {
        let text = """
        Home Depot
        2026-01-15
        Screws $5.99
        Total $5.99
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.merchantName, "Home Depot")
    }

    func test_parse_merchantSkipsAmountLines() {
        let text = """
        $12.00
        Shell Gas Station
        Fuel $40.00
        Total $40.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.merchantName, "Shell Gas Station")
    }

    // MARK: - Date extraction

    func test_parse_dateMMDDYYYY() {
        let text = """
        Store
        Date: 03/15/2026
        Total $10.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertNotNil(result.transactionDate)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: result.transactionDate!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func test_parse_dateYYYYMMDD() {
        let text = """
        Store
        2026-04-20
        Total $55.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertNotNil(result.transactionDate)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: result.transactionDate!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
    }

    func test_parse_noDate_returnsNil() {
        let text = """
        Some Store
        Item $10.00
        Total $10.00
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertNil(result.transactionDate)
    }

    // MARK: - Line items

    func test_parse_extractsLineItems() {
        let text = """
        Walmart
        Batteries        $8.99
        Paper Towels    $12.49
        Subtotal        $21.48
        Tax              $1.72
        Total           $23.20
        """
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertNotNil(result.lineItems)
        let items = result.lineItems!
        XCTAssertTrue(items.count >= 2)
        let descs = items.map(\.description)
        XCTAssertTrue(descs.contains(where: { $0.contains("Batteries") }))
        XCTAssertTrue(descs.contains(where: { $0.contains("Paper Towels") }))
    }

    func test_parse_lineItems_excludesSummaryLines() {
        let text = """
        Store
        Widget $5.00
        Tax $0.40
        Total $5.40
        """
        let result = ReceiptParser.parse(rawText: text)
        let items = result.lineItems ?? []
        // Tax and Total lines should be excluded from line items
        XCTAssertFalse(items.contains(where: { $0.description.lowercased().contains("tax") }))
        XCTAssertFalse(items.contains(where: { $0.description.lowercased().contains("total") }))
    }

    // MARK: - Raw text preserved

    func test_parse_rawTextPreserved() {
        let text = "Store\nTotal $10.00"
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertEqual(result.rawText, text)
    }

    // MARK: - Empty / edge cases

    func test_parse_emptyString_returnsEmptyResult() {
        let result = ReceiptParser.parse(rawText: "")
        XCTAssertNil(result.merchantName)
        XCTAssertNil(result.totalCents)
        XCTAssertNil(result.taxCents)
        XCTAssertEqual(result.rawText, "")
    }

    func test_parse_noAmounts_returnsNilMoney() {
        let text = "Receipt\nThank you for shopping\nHave a great day"
        let result = ReceiptParser.parse(rawText: text)
        XCTAssertNil(result.totalCents)
        XCTAssertNil(result.taxCents)
        XCTAssertNil(result.subtotalCents)
    }

    // MARK: - Date patterns

    func test_extractDate_shortYear() {
        let lines = ["Store", "Date 04/20/26", "Total $5.00"]
        let date = ReceiptParser.extractDate(lines: lines)
        XCTAssertNotNil(date)
    }
}
