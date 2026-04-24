import XCTest
@testable import Customers
import Networking

// MARK: - CustomerLTVTests (§44)
//
// Tests for CustomerLTVResult factories covering:
//   - empty invoice array → bronze $0
//   - high-volume invoice array → platinum
//   - from(detail:) with ltv_cents / total_spent_cents / nil
//   - from(analytics:) LTV calculation
//   - formatted() currency string
//   - tier boundary values

final class CustomerLTVTests: XCTestCase {

    // MARK: - InvoiceSummary guards

    func test_invoiceSummary_rejectsNegativeDollars() {
        let invoice = InvoiceSummary(totalDollars: -50)
        XCTAssertEqual(invoice.totalDollars, 0)
    }

    func test_invoiceSummary_fromCents_convertsCorrectly() {
        let invoice = InvoiceSummary(totalCents: 150_000)
        XCTAssertEqual(invoice.totalDollars, 1_500, accuracy: 0.01)
    }

    // MARK: - from(invoices:) — empty

    func test_fromInvoices_empty_isBronze_zeroDollars() {
        let result = CustomerLTVResult.from(invoices: [])
        XCTAssertEqual(result.lifetimeDollars, 0)
        XCTAssertEqual(result.tier, .bronze)
        XCTAssertEqual(result.invoiceCount, 0)
    }

    // MARK: - from(invoices:) — tier boundaries

    func test_fromInvoices_499dollars_isBronze() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 499)])
        XCTAssertEqual(result.tier, .bronze)
    }

    func test_fromInvoices_500dollars_isSilver() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 500)])
        XCTAssertEqual(result.tier, .silver)
    }

    func test_fromInvoices_1499dollars_isSilver() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 1_499)])
        XCTAssertEqual(result.tier, .silver)
    }

    func test_fromInvoices_1500dollars_isGold() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 1_500)])
        XCTAssertEqual(result.tier, .gold)
    }

    func test_fromInvoices_4999dollars_isGold() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 4_999)])
        XCTAssertEqual(result.tier, .gold)
    }

    func test_fromInvoices_5000dollars_isPlatinum() {
        let result = CustomerLTVResult.from(invoices: [InvoiceSummary(totalDollars: 5_000)])
        XCTAssertEqual(result.tier, .platinum)
    }

    // MARK: - from(invoices:) — multi-invoice sum

    func test_fromInvoices_multipleInvoices_sumsCorrectly() {
        let invoices = [
            InvoiceSummary(totalDollars: 200),
            InvoiceSummary(totalDollars: 350),
            InvoiceSummary(totalDollars: 100),
        ]
        let result = CustomerLTVResult.from(invoices: invoices)
        XCTAssertEqual(result.lifetimeDollars, 650, accuracy: 0.01)
        XCTAssertEqual(result.tier, .silver)
        XCTAssertEqual(result.invoiceCount, 3)
    }

    // MARK: - from(invoices:) — high-volume

    func test_fromInvoices_100invoices_isPlatinum() {
        let invoices = (0..<100).map { _ in InvoiceSummary(totalDollars: 100) }
        let result = CustomerLTVResult.from(invoices: invoices)
        XCTAssertEqual(result.lifetimeDollars, 10_000, accuracy: 0.01)
        XCTAssertEqual(result.tier, .platinum)
        XCTAssertEqual(result.invoiceCount, 100)
    }

    // MARK: - from(detail:) — server ltv_cents

    func test_fromDetail_withLtvCents_usesThatValue() {
        let detail = makeDetail(ltvCents: 200_000)   // $2 000 → gold
        let result = CustomerLTVResult.from(detail: detail)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.lifetimeDollars, 2_000, accuracy: 0.01)
        XCTAssertEqual(result!.tier, .gold)
    }

    func test_fromDetail_withTotalSpentCents_fallsBack() {
        let detail = makeDetail(totalSpentCents: 50_000)  // $500 → silver
        let result = CustomerLTVResult.from(detail: detail)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.tier, .silver)
    }

    func test_fromDetail_withBothFields_prefersLtvCents() {
        let detail = makeDetail(ltvCents: 600_000, totalSpentCents: 50_000)
        let result = CustomerLTVResult.from(detail: detail)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.lifetimeDollars, 6_000, accuracy: 0.01)
        XCTAssertEqual(result!.tier, .platinum)
    }

    func test_fromDetail_noFields_returnsNil() {
        let detail = makeDetail()
        let result = CustomerLTVResult.from(detail: detail)
        XCTAssertNil(result)
    }

    func test_fromDetail_zeroLtvCents_returnsNil() {
        let detail = makeDetail(ltvCents: 0)
        let result = CustomerLTVResult.from(detail: detail)
        XCTAssertNil(result)
    }

    // MARK: - from(analytics:)

    func test_fromAnalytics_lifetimeValue_computesTier() {
        let analytics = makeAnalytics(lifetimeValue: 3_000, totalTickets: 42)
        let result = CustomerLTVResult.from(analytics: analytics)
        XCTAssertEqual(result.lifetimeDollars, 3_000, accuracy: 0.01)
        XCTAssertEqual(result.tier, .gold)
        XCTAssertEqual(result.invoiceCount, 42)
    }

    func test_fromAnalytics_zeroLTV_isBronze() {
        let analytics = makeAnalytics(lifetimeValue: 0, totalTickets: 0)
        let result = CustomerLTVResult.from(analytics: analytics)
        XCTAssertEqual(result.tier, .bronze)
        XCTAssertEqual(result.invoiceCount, 0)
    }

    // MARK: - Formatted output

    func test_formatted_wholeDollarAmount() {
        let result = CustomerLTVResult(lifetimeDollars: 1_000, tier: .silver, invoiceCount: 0)
        // Formatted should start with "$" and contain "1,000"
        XCTAssertTrue(result.formatted.contains("1,000") || result.formatted.contains("1000"),
                      "Expected formatted to contain 1000, got \(result.formatted)")
    }

    func test_formatted_fractionalAmount() {
        let result = CustomerLTVResult(lifetimeDollars: 1_249.50, tier: .gold, invoiceCount: 0)
        XCTAssertTrue(result.formatted.contains("1,249") || result.formatted.contains("1249"),
                      "Expected formatted to contain 1249, got \(result.formatted)")
        XCTAssertTrue(result.formatted.contains("50") || result.formatted.contains(".5"),
                      "Expected fractional part in \(result.formatted)")
    }

    // MARK: - Custom thresholds

    func test_customThresholds_overrideDefault() {
        let thresholds = LTVThresholds(silverCents: 10_000, goldCents: 30_000, platinumCents: 60_000)
        let result = CustomerLTVResult.from(
            invoices: [InvoiceSummary(totalDollars: 250)],
            thresholds: thresholds
        )
        // $250 = 25_000 cents → silver with custom thresholds (≥ 10_000)
        XCTAssertEqual(result.tier, .silver)
    }

    // MARK: - Rounding

    func test_lifetimeDollars_roundedToTwoDecimalPlaces() {
        let result = CustomerLTVResult(lifetimeDollars: 1_000.123456, tier: .silver, invoiceCount: 0)
        // Should be rounded to 1000.12
        XCTAssertEqual(result.lifetimeDollars, 1_000.12, accuracy: 0.001)
    }
}

// MARK: - Helpers

private func makeDetail(ltvCents: Int64? = nil, totalSpentCents: Int64? = nil) -> CustomerDetail {
    var fields = ["\"id\": 1"]
    if let v = ltvCents        { fields.append("\"ltv_cents\": \(v)") }
    if let v = totalSpentCents { fields.append("\"total_spent_cents\": \(v)") }
    let json = "{\(fields.joined(separator: ", "))}".data(using: .utf8)!
    return try! JSONDecoder().decode(CustomerDetail.self, from: json)
}

private func makeAnalytics(lifetimeValue: Double, totalTickets: Int) -> CustomerAnalytics {
    let json = """
    {
        "lifetime_value": \(lifetimeValue),
        "total_tickets": \(totalTickets)
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(CustomerAnalytics.self, from: json)
}
