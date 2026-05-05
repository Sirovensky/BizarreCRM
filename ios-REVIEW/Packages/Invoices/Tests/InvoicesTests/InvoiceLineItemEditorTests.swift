import XCTest
@testable import Invoices
import Networking

// MARK: - EditableLineItemTests

final class EditableLineItemTests: XCTestCase {

    private func makeItem(
        id: Int64 = 1,
        quantity: Double = 2,
        unitPrice: Double = 10.0,
        lineDiscount: Double = 0,
        taxAmount: Double = 0
    ) -> InvoiceDetail.LineItem {
        // Approximate LineItem via the Decodable path (use JSON decode)
        let json = """
        {
            "id": \(id),
            "invoice_id": 100,
            "item_name": "Widget",
            "quantity": \(quantity),
            "unit_price": \(unitPrice),
            "line_discount": \(lineDiscount),
            "tax_amount": \(taxAmount),
            "total": \(quantity * unitPrice - lineDiscount + taxAmount)
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(InvoiceDetail.LineItem.self, from: json)
    }

    func test_lineTotal_quantityTimesUnitPrice() {
        let source = makeItem(quantity: 3, unitPrice: 15.0)
        let line = EditableLineItem(from: source)
        XCTAssertEqual(line.lineTotal, 45.0, accuracy: 0.001)
    }

    func test_lineTotal_respectsDiscount() {
        let source = makeItem(quantity: 2, unitPrice: 20.0, lineDiscount: 5.0)
        let line = EditableLineItem(from: source)
        // 2*20 - 5 = 35
        XCTAssertEqual(line.lineTotal, 35.0, accuracy: 0.001)
    }

    func test_lineTotal_addsTax() {
        let source = makeItem(quantity: 1, unitPrice: 50.0, taxAmount: 4.0)
        var line = EditableLineItem(from: source)
        XCTAssertEqual(line.lineTotal, 54.0, accuracy: 0.001)
    }

    func test_init_populatesDescription() {
        let source = makeItem()
        let line = EditableLineItem(from: source)
        XCTAssertFalse(line.description.isEmpty)
    }

    func test_init_preservesId() {
        let source = makeItem(id: 42)
        let line = EditableLineItem(from: source)
        XCTAssertEqual(line.id, 42)
    }
}

// MARK: - InvoiceDetailCanEditLinesTests

final class InvoiceDetailCanEditLinesTests: XCTestCase {

    private func makeDetail(status: String, amountPaid: Double) -> InvoiceDetail {
        let json = """
        {
            "id": 1,
            "status": "\(status)",
            "amount_paid": \(amountPaid),
            "total": 100.0
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(InvoiceDetail.self, from: json)
    }

    func test_canEditLines_draftNoPay_isTrue() {
        let inv = makeDetail(status: "draft", amountPaid: 0)
        XCTAssertTrue(inv.canEditLines)
    }

    func test_canEditLines_unpaidNoPay_isTrue() {
        let inv = makeDetail(status: "unpaid", amountPaid: 0)
        XCTAssertTrue(inv.canEditLines)
    }

    func test_canEditLines_paid_isFalse() {
        let inv = makeDetail(status: "paid", amountPaid: 100)
        XCTAssertFalse(inv.canEditLines)
    }

    func test_canEditLines_void_isFalse() {
        let inv = makeDetail(status: "void", amountPaid: 0)
        XCTAssertFalse(inv.canEditLines)
    }

    func test_canEditLines_partial_isFalse() {
        let inv = makeDetail(status: "partial", amountPaid: 50)
        XCTAssertFalse(inv.canEditLines)
    }

    func test_canEditLines_unpaidWithPayments_isFalse() {
        let inv = makeDetail(status: "unpaid", amountPaid: 10)
        XCTAssertFalse(inv.canEditLines)
    }

    // MARK: - isOverpaid

    func test_isOverpaid_paidMoreThanTotal_isTrue() {
        let inv = makeDetail(status: "paid", amountPaid: 110)
        XCTAssertTrue(inv.isOverpaid)
    }

    func test_isOverpaid_paidExactTotal_isFalse() {
        let inv = makeDetail(status: "paid", amountPaid: 100)
        XCTAssertFalse(inv.isOverpaid)
    }

    func test_isOverpaid_underpaid_isFalse() {
        let inv = makeDetail(status: "partial", amountPaid: 50)
        XCTAssertFalse(inv.isOverpaid)
    }
}

// MARK: - InvoiceConvertFromTicketViewModelTests

@MainActor
final class InvoiceConvertFromTicketViewModelTests: XCTestCase {

    func test_canConvert_withValidInt_isTrue() {
        let vm = InvoiceConvertFromTicketViewModel(api: StubConvertAPIClient())
        vm.ticketId = "1042"
        XCTAssertTrue(vm.canConvert)
    }

    func test_canConvert_withEmptyString_isFalse() {
        let vm = InvoiceConvertFromTicketViewModel(api: StubConvertAPIClient())
        vm.ticketId = ""
        XCTAssertFalse(vm.canConvert)
    }

    func test_canConvert_withAlphaString_isFalse() {
        let vm = InvoiceConvertFromTicketViewModel(api: StubConvertAPIClient())
        vm.ticketId = "abc"
        XCTAssertFalse(vm.canConvert)
    }
}

// MARK: - InvoiceConvertFromEstimateViewModelTests

@MainActor
final class InvoiceConvertFromEstimateViewModelTests: XCTestCase {

    func test_canConvert_withValidInt_isTrue() {
        let vm = InvoiceConvertFromEstimateViewModel(api: StubConvertAPIClient())
        vm.estimateId = "205"
        XCTAssertTrue(vm.canConvert)
    }

    func test_canConvert_withEmpty_isFalse() {
        let vm = InvoiceConvertFromEstimateViewModel(api: StubConvertAPIClient())
        vm.estimateId = ""
        XCTAssertFalse(vm.canConvert)
    }
}

// MARK: - StubConvertAPIClient (minimal stub for conversion tests)

private final class StubConvertAPIClient: APIClient {
    // Not testing network calls; just ViewModel behaviour.
}
