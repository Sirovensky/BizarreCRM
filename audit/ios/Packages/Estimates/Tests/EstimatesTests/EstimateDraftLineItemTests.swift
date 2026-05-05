import XCTest
@testable import Estimates
import Networking

// MARK: - EstimateDraftLineItemTests

/// Tests for EstimateDraft.LineItemDraft and endpoint response decoding.

final class EstimateDraftLineItemTests: XCTestCase {

    // MARK: - toRequest: valid item

    func test_toRequest_validItem_returnsRequest() {
        let item = EstimateDraft.LineItemDraft(
            description: "Battery replacement",
            quantity: "2",
            unitPrice: "49.99",
            taxAmount: "5.00"
        )
        let req = item.toRequest()
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.description, "Battery replacement")
        XCTAssertEqual(req?.quantity, 2)
        XCTAssertEqual(req?.unitPrice ?? 0, 49.99, accuracy: 0.001)
        XCTAssertEqual(req?.taxAmount ?? 0, 5.0, accuracy: 0.001)
    }

    func test_toRequest_taxDefaultsToZero() {
        let item = EstimateDraft.LineItemDraft(
            description: "Labor",
            quantity: "1",
            unitPrice: "75.00"
            // taxAmount defaults to "0"
        )
        let req = item.toRequest()
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.taxAmount ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - toRequest: invalid items

    func test_toRequest_emptyDescription_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "   ", quantity: "1", unitPrice: "10")
        XCTAssertNil(item.toRequest())
    }

    func test_toRequest_zeroQuantity_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "A", quantity: "0", unitPrice: "10")
        XCTAssertNil(item.toRequest())
    }

    func test_toRequest_negativeQuantity_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "A", quantity: "-1", unitPrice: "10")
        XCTAssertNil(item.toRequest())
    }

    func test_toRequest_invalidQuantityString_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "A", quantity: "abc", unitPrice: "10")
        XCTAssertNil(item.toRequest())
    }

    func test_toRequest_emptyPrice_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "")
        XCTAssertNil(item.toRequest())
    }

    func test_toRequest_invalidPriceString_returnsNil() {
        let item = EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "xyz")
        XCTAssertNil(item.toRequest())
    }

    // MARK: - Codable round-trip

    func test_draft_codableRoundTrip() throws {
        let original = EstimateDraft(
            customerId: "42",
            customerDisplayName: "Acme Corp",
            notes: "Test notes",
            validUntil: "2026-06-30",
            discount: "10.00",
            lineItems: [
                EstimateDraft.LineItemDraft(description: "Widget", quantity: "3", unitPrice: "20.00", taxAmount: "1.50")
            ]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EstimateDraft.self, from: encoded)

        XCTAssertEqual(decoded.customerId, original.customerId)
        XCTAssertEqual(decoded.customerDisplayName, original.customerDisplayName)
        XCTAssertEqual(decoded.notes, original.notes)
        XCTAssertEqual(decoded.discount, original.discount)
        XCTAssertEqual(decoded.lineItems.count, 1)
        XCTAssertEqual(decoded.lineItems[0].description, "Widget")
        XCTAssertEqual(decoded.lineItems[0].quantity, "3")
    }

    // MARK: - Equatable

    func test_lineItemDraft_equatable_sameId_equal() {
        let a = EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "10")
        var b = a
        b.description = "B"
        // Different id → not equal
        let c = EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "10")
        XCTAssertNotEqual(a, c)  // different UUID
        // Same reference (copy) with mutated description → not equal
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ConvertEstimateResponse decoding

    func test_convertResponse_decodesTicketId() throws {
        let json = """
        {"ticket":{"id":99,"order_id":"T-99","status_id":1},"message":"Estimate converted to ticket"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ConvertEstimateResponse.self, from: json)
        XCTAssertEqual(response.ticketId, 99)
    }

    func test_convertResponse_missingTicket_throws() {
        let json = """
        {"message":"ok"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ConvertEstimateResponse.self, from: json))
    }

    // MARK: - EstimateLineItem decoding

    func test_estimateLineItem_decodes() throws {
        let json = """
        {
          "id": 5,
          "estimate_id": 3,
          "inventory_item_id": 10,
          "description": "Screen repair",
          "quantity": 1,
          "unit_price": 129.99,
          "tax_amount": 9.75,
          "total": 139.74,
          "item_name": "iPhone Screen",
          "item_sku": "SCR-001"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let item = try decoder.decode(EstimateLineItem.self, from: json)
        XCTAssertEqual(item.id, 5)
        XCTAssertEqual(item.description, "Screen repair")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unitPrice ?? 0, 129.99, accuracy: 0.001)
        XCTAssertEqual(item.itemSku, "SCR-001")
    }

    // MARK: - Estimate with lineItems decodes

    func test_estimate_withLineItems_decodes() throws {
        let json = """
        {
          "id": 1,
          "order_id": "EST-1",
          "customer_id": 2,
          "customer_first_name": "Alice",
          "customer_last_name": "Smith",
          "status": "approved",
          "total": 139.74,
          "line_items": [
            {
              "id": 5,
              "estimate_id": 1,
              "description": "Screen repair",
              "quantity": 1,
              "unit_price": 129.99,
              "tax_amount": 9.75,
              "total": 139.74
            }
          ]
        }
        """.data(using: .utf8)!
        // Estimate uses explicit CodingKeys (snake_case literals) — do NOT use
        // convertFromSnakeCase or it double-converts the key names.
        let decoder = JSONDecoder()
        let estimate = try decoder.decode(Estimate.self, from: json)
        XCTAssertEqual(estimate.status, "approved")
        XCTAssertEqual(estimate.lineItems?.count, 1)
        XCTAssertEqual(estimate.lineItems?[0].description, "Screen repair")
    }
}
