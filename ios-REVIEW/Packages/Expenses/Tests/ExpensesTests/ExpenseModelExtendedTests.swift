import XCTest
@testable import Networking

/// Tests for the extended `Expense` model (new phase-4 fields).
final class ExpenseModelExtendedTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - New fields decode correctly

    func testDecodesVendor() throws {
        let json = #"{"id":1,"vendor":"Home Depot"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.vendor, "Home Depot")
    }

    func testDecodesTaxAmount() throws {
        let json = #"{"id":2,"tax_amount":8.5}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(try XCTUnwrap(e.taxAmount), 8.5, accuracy: 0.001)
    }

    func testDecodesPaymentMethod() throws {
        let json = #"{"id":3,"payment_method":"Credit Card"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.paymentMethod, "Credit Card")
    }

    func testDecodesNotes() throws {
        let json = #"{"id":4,"notes":"Business trip"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.notes, "Business trip")
    }

    func testDecodesIsReimbursableTrue() throws {
        let json = #"{"id":5,"is_reimbursable":true}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.isReimbursable, true)
    }

    func testDecodesIsReimbursableFalse() throws {
        let json = #"{"id":6,"is_reimbursable":false}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.isReimbursable, false)
    }

    func testDecodesStatus() throws {
        let json = #"{"id":7,"status":"pending"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.status, "pending")
    }

    func testDecodesReceiptImagePath() throws {
        let json = #"{"id":8,"receipt_image_path":"/uploads/receipts/r8.jpg"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.receiptImagePath, "/uploads/receipts/r8.jpg")
    }

    func testDecodesReceiptUploadedAt() throws {
        let json = #"{"id":9,"receipt_uploaded_at":"2026-03-20T10:00:00Z"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.receiptUploadedAt, "2026-03-20T10:00:00Z")
    }

    func testDecodesExpenseSubtype() throws {
        let json = #"{"id":10,"expense_subtype":"mileage"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.expenseSubtype, "mileage")
    }

    func testDecodesApprovedByUserId() throws {
        let json = #"{"id":11,"approved_by_user_id":7}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.approvedByUserId, 7)
    }

    func testDecodesApprovedAt() throws {
        let json = #"{"id":12,"approved_at":"2026-03-21T12:00:00Z"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.approvedAt, "2026-03-21T12:00:00Z")
    }

    func testDecodesDenialReason() throws {
        let json = #"{"id":13,"denial_reason":"Insufficient docs"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.denialReason, "Insufficient docs")
    }

    // MARK: - resolvedReceiptPath helper

    func testResolvedReceiptPathPrefersImagePath() throws {
        let json = #"{"id":14,"receipt_path":"old.jpg","receipt_image_path":"new.jpg"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.resolvedReceiptPath, "new.jpg")
    }

    func testResolvedReceiptPathFallsBackToPath() throws {
        let json = #"{"id":15,"receipt_path":"legacy.jpg"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.resolvedReceiptPath, "legacy.jpg")
    }

    func testResolvedReceiptPathNilWhenBothAbsent() throws {
        let json = #"{"id":16}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertNil(e.resolvedReceiptPath)
    }

    // MARK: - approvalStatus helper

    func testApprovalStatusPending() throws {
        let json = #"{"id":17,"status":"pending"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.approvalStatus, .pending)
    }

    func testApprovalStatusApproved() throws {
        let json = #"{"id":18,"status":"approved"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.approvalStatus, .approved)
    }

    func testApprovalStatusDenied() throws {
        let json = #"{"id":19,"status":"denied"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(e.approvalStatus, .denied)
    }

    func testApprovalStatusNilWhenAbsent() throws {
        let json = #"{"id":20}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertNil(e.approvalStatus)
    }

    func testApprovalStatusNilForUnknownValue() throws {
        let json = #"{"id":21,"status":"unknown_status"}"#.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertNil(e.approvalStatus)
    }

    // MARK: - Null values for new fields

    func testAllNewFieldsNullable() throws {
        let json = """
        {
            "id": 22,
            "vendor": null,
            "tax_amount": null,
            "payment_method": null,
            "notes": null,
            "is_reimbursable": null,
            "status": null,
            "receipt_image_path": null,
            "receipt_uploaded_at": null,
            "expense_subtype": null,
            "approved_by_user_id": null,
            "approved_at": null,
            "denial_reason": null
        }
        """.data(using: .utf8)!
        let e = try decoder.decode(Expense.self, from: json)
        XCTAssertNil(e.vendor)
        XCTAssertNil(e.taxAmount)
        XCTAssertNil(e.paymentMethod)
        XCTAssertNil(e.notes)
        XCTAssertNil(e.isReimbursable)
        XCTAssertNil(e.status)
        XCTAssertNil(e.receiptImagePath)
        XCTAssertNil(e.receiptUploadedAt)
        XCTAssertNil(e.expenseSubtype)
        XCTAssertNil(e.approvedByUserId)
        XCTAssertNil(e.approvedAt)
        XCTAssertNil(e.denialReason)
    }

    // MARK: - ExpenseCategory enum

    func testExpenseCategoryAllCasesPresent() {
        // Verify key categories exist for picker
        let cases = ExpenseCategory.allCases.map(\.rawValue)
        XCTAssertTrue(cases.contains("Rent"))
        XCTAssertTrue(cases.contains("Utilities"))
        XCTAssertTrue(cases.contains("Travel"))
        XCTAssertTrue(cases.contains("Other"))
        XCTAssertGreaterThanOrEqual(cases.count, 10)
    }

    // MARK: - PaymentMethod enum

    func testPaymentMethodAllCasesPresent() {
        let cases = PaymentMethod.allCases.map(\.rawValue)
        XCTAssertTrue(cases.contains("Cash"))
        XCTAssertTrue(cases.contains("Credit Card"))
        XCTAssertTrue(cases.contains("Debit Card"))
        XCTAssertGreaterThanOrEqual(cases.count, 5)
    }

    // MARK: - CreateExpenseRequest encodes

    func testCreateExpenseRequestEncodesCategory() throws {
        let req = CreateExpenseRequest(category: "Tools", amount: 50.0)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["category"] as? String, "Tools")
        XCTAssertEqual(dict["amount"] as? Double, 50.0)
    }

    func testCreateExpenseRequestEncodesSnakeCaseKeys() throws {
        let req = CreateExpenseRequest(
            category: "Tools",
            amount: 100.0,
            taxAmount: 8.5,
            paymentMethod: "Cash",
            isReimbursable: true
        )
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["tax_amount"] as? Double, 8.5, accuracy: 0.001)
        XCTAssertEqual(dict["payment_method"] as? String, "Cash")
        XCTAssertEqual(dict["is_reimbursable"] as? Bool, true)
    }

    // MARK: - UpdateExpenseRequest encodes

    func testUpdateExpenseRequestAllNilByDefault() throws {
        let req = UpdateExpenseRequest()
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // All fields should be absent from dict when nil
        // JSONEncoder omits nil optionals by default (they encode to null)
        XCTAssertFalse(dict.keys.contains("amount") && dict["amount"] != nil)
    }

    func testUpdateExpenseRequestPartialUpdate() throws {
        let req = UpdateExpenseRequest(category: "Rent", amount: 1500.0)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["category"] as? String, "Rent")
        XCTAssertEqual(dict["amount"] as? Double, 1500.0, accuracy: 0.001)
    }

    // MARK: - ExpenseReceiptUploadResponse decodes

    func testReceiptUploadResponseDecodes() throws {
        let json = """
        {
            "id": 5,
            "expense_id": 42,
            "file_path": "/uploads/receipts/abc.jpg",
            "mime_type": "image/jpeg",
            "ocr_status": "pending",
            "created_at": "2026-03-20T10:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(ExpenseReceiptUploadResponse.self, from: json)
        XCTAssertEqual(r.id, 5)
        XCTAssertEqual(r.expenseId, 42)
        XCTAssertEqual(r.filePath, "/uploads/receipts/abc.jpg")
        XCTAssertEqual(r.mimeType, "image/jpeg")
        XCTAssertEqual(r.ocrStatus, "pending")
    }

    // MARK: - ExpenseReceiptStatusResponse decodes

    func testReceiptStatusResponseDecodes() throws {
        let json = """
        {
            "expense_id": 7,
            "receipt_image_path": "/uploads/receipts/r7.jpg",
            "receipt_ocr_text": "Total: $45.00",
            "receipt_uploaded_at": "2026-03-21T09:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(ExpenseReceiptStatusResponse.self, from: json)
        XCTAssertEqual(r.expenseId, 7)
        XCTAssertEqual(r.receiptImagePath, "/uploads/receipts/r7.jpg")
        XCTAssertEqual(r.receiptOcrText, "Total: $45.00")
    }
}
