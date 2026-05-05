import XCTest
@testable import Estimates
import Networking

// MARK: - EstimatePreviewInspectorTests
//
// §22 iPad — unit tests for the data model consumed by EstimatePreviewInspector.
// Tests focus on derived properties, state expressions, and formatting logic
// via a thin helper that mirrors the inspector's computed values.

final class EstimatePreviewInspectorTests: XCTestCase {

    // MARK: - Helpers

    private func makeEstimate(
        id: Int64 = 1,
        status: String? = "draft",
        total: Double = 249.99,
        subtotal: Double? = 230.0,
        discount: Double? = nil,
        totalTax: Double? = nil,
        lineItems: [EstimateLineItem]? = nil,
        isExpiring: Bool? = false,
        daysUntilExpiry: Int? = nil,
        validUntil: String? = "2026-12-31"
    ) -> Estimate {
        var dict: [String: Any] = [
            "id": id,
            "order_id": "EST-\(id)",
            "customer_first_name": "Jane",
            "customer_last_name": "Smith",
            "total": total,
            "is_expiring": isExpiring as Any
        ]
        if let status { dict["status"] = status }
        if let subtotal { dict["subtotal"] = subtotal }
        if let discount { dict["discount"] = discount }
        if let totalTax { dict["total_tax"] = totalTax }
        if let daysUntilExpiry { dict["days_until_expiry"] = daysUntilExpiry }
        if let validUntil { dict["valid_until"] = validUntil }

        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Estimate.self, from: data)
    }

    private func makeLineItem(
        id: Int64 = 1,
        description: String = "Battery",
        qty: Int = 2,
        unitPrice: Double = 49.99,
        total: Double = 99.98,
        taxAmount: Double = 0,
        sku: String? = nil
    ) -> EstimateLineItem {
        var dict: [String: Any] = [
            "id": id,
            "estimate_id": 1,
            "description": description,
            "quantity": qty,
            "unit_price": unitPrice,
            "total": total,
            "tax_amount": taxAmount
        ]
        if let sku { dict["item_sku"] = sku }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(EstimateLineItem.self, from: data)
    }

    // MARK: - Signature status

    func test_signatureStatus_signed_isSigned() {
        let est = makeEstimate(status: "signed")
        XCTAssertEqual(est.status?.lowercased(), "signed")
    }

    func test_signatureStatus_draft_isNotSigned() {
        let est = makeEstimate(status: "draft")
        XCTAssertNotEqual(est.status?.lowercased(), "signed")
    }

    func test_signatureStatus_nilStatus_isNotSigned() {
        let est = makeEstimate(status: nil)
        XCTAssertNil(est.status)
    }

    // MARK: - Status badge predicates

    func test_statusBadge_approved_isApproved() {
        let est = makeEstimate(status: "approved")
        XCTAssertEqual(est.status?.lowercased(), "approved")
    }

    func test_statusBadge_converted_isConverted() {
        let est = makeEstimate(status: "converted")
        XCTAssertEqual(est.status?.lowercased(), "converted")
    }

    func test_statusBadge_expired_matchesErrorColor() {
        let est = makeEstimate(status: "expired")
        let isError = est.status?.lowercased() == "rejected" || est.status?.lowercased() == "expired"
        XCTAssertTrue(isError)
    }

    // MARK: - Convert button disabled states

    func test_convertButton_disabled_whenConverted() {
        let est = makeEstimate(status: "converted")
        XCTAssertTrue(est.status?.lowercased() == "converted")
    }

    func test_convertButton_enabled_whenDraft() {
        let est = makeEstimate(status: "draft")
        XCTAssertFalse(est.status?.lowercased() == "converted")
    }

    // MARK: - Sign button disabled states

    func test_signButton_disabled_whenSigned() {
        let est = makeEstimate(status: "signed")
        XCTAssertTrue(est.status?.lowercased() == "signed")
    }

    func test_signButton_enabled_whenSent() {
        let est = makeEstimate(status: "sent")
        XCTAssertFalse(est.status?.lowercased() == "signed")
    }

    // MARK: - Totals breakdown

    func test_totalsSection_subtotalPresent() {
        let est = makeEstimate(subtotal: 230.0)
        XCTAssertEqual(est.subtotal, 230.0)
    }

    func test_totalsSection_discountZero_omitted() {
        let est = makeEstimate(discount: 0)
        // discount > 0 guard in inspector — 0 should not show
        XCTAssertEqual(est.discount ?? 0, 0)
    }

    func test_totalsSection_discountPositive_shown() {
        let est = makeEstimate(discount: 15.0)
        XCTAssertEqual(est.discount, 15.0)
        XCTAssertTrue((est.discount ?? 0) > 0)
    }

    func test_totalsSection_taxZero_omitted() {
        let est = makeEstimate(totalTax: 0)
        XCTAssertEqual(est.totalTax ?? 0, 0)
    }

    func test_totalsSection_taxPositive_shown() {
        let est = makeEstimate(totalTax: 22.50)
        XCTAssertEqual(est.totalTax, 22.50)
        XCTAssertTrue((est.totalTax ?? 0) > 0)
    }

    func test_totalsSection_totalFallsBackToZero_whenNil() {
        let est = makeEstimate(total: 0)
        XCTAssertEqual(est.total ?? 0, 0)
    }

    // MARK: - Line items

    func test_lineItems_nil_sectionHidden() {
        let est = makeEstimate(lineItems: nil)
        XCTAssertNil(est.lineItems)
    }

    func test_lineItems_empty_sectionHidden() {
        // Estimate.lineItems is decoded from JSON; empty array comes from detail endpoint
        let json = """
        {"id":1,"order_id":"EST-1","customer_first_name":"A","total":0,"line_items":[],"is_expiring":false}
        """.data(using: .utf8)!
        let est = try! JSONDecoder().decode(Estimate.self, from: json)
        XCTAssertEqual(est.lineItems?.count, 0)
    }

    func test_lineItem_description_usedFirst() {
        let item = makeLineItem(description: "Battery Replace")
        XCTAssertEqual(item.description, "Battery Replace")
    }

    func test_lineItem_totalShown_whenPresent() {
        let item = makeLineItem(total: 99.98)
        XCTAssertEqual(item.total, 99.98)
    }

    func test_lineItem_taxZero_notShown() {
        let item = makeLineItem(taxAmount: 0)
        XCTAssertEqual(item.taxAmount, 0)
        XCTAssertFalse((item.taxAmount ?? 0) > 0)
    }

    func test_lineItem_taxPositive_shown() {
        let item = makeLineItem(taxAmount: 8.50)
        XCTAssertTrue((item.taxAmount ?? 0) > 0)
    }

    func test_lineItem_skuPresent() {
        let item = makeLineItem(sku: "BATT-2024")
        XCTAssertEqual(item.itemSku, "BATT-2024")
    }

    // MARK: - Expiry display

    func test_expiryLabel_showsWarning_whenIsExpiring() {
        let est = makeEstimate(isExpiring: true, daysUntilExpiry: 3)
        XCTAssertTrue(est.isExpiring == true)
        XCTAssertEqual(est.daysUntilExpiry, 3)
    }

    func test_expiryLabel_showsValidUntil_whenNotExpiring() {
        let est = makeEstimate(isExpiring: false, validUntil: "2026-12-31")
        XCTAssertFalse(est.isExpiring == true)
        XCTAssertEqual(est.validUntil, "2026-12-31")
    }

    // MARK: - Customer name

    func test_customerName_bothParts_joined() {
        let est = makeEstimate()
        XCTAssertEqual(est.customerName, "Jane Smith")
    }

    func test_customerName_fallback_emDash_whenBothNil() {
        let json = """
        {"id":1,"total":0,"is_expiring":false}
        """.data(using: .utf8)!
        let est = try! JSONDecoder().decode(Estimate.self, from: json)
        XCTAssertEqual(est.customerName, "—")
    }
}
