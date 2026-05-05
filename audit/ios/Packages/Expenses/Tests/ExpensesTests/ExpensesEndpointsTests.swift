import XCTest
@testable import Networking

/// Tests that `Expense` and `ExpensesListResponse` decode correctly from
/// server-shaped JSON (snake_case keys, optional fields).
final class ExpensesEndpointsTests: XCTestCase {

    // MARK: - Expense decode: required fields only

    func testExpenseDecodesRequiredFields() throws {
        let json = """
        {
            "id": 42,
            "category": "office",
            "amount": 19.99,
            "first_name": "Alice",
            "last_name": "Smith"
        }
        """.data(using: .utf8)!

        let expense = try decoder.decode(Expense.self, from: json)

        XCTAssertEqual(expense.id, 42)
        XCTAssertEqual(expense.category, "office")
        XCTAssertEqual(try XCTUnwrap(expense.amount), 19.99, accuracy: 0.001)
        XCTAssertEqual(expense.firstName, "Alice")
        XCTAssertEqual(expense.lastName, "Smith")
        XCTAssertNil(expense.description)
        XCTAssertNil(expense.date)
        XCTAssertNil(expense.receiptPath)
        XCTAssertNil(expense.userId)
        XCTAssertNil(expense.createdAt)
        XCTAssertNil(expense.updatedAt)
    }

    // MARK: - Expense decode: full payload with all optional fields

    func testExpenseDecodesAllFields() throws {
        let json = """
        {
            "id": 7,
            "category": "travel",
            "amount": 250.00,
            "description": "Flight to SF",
            "date": "2026-03-15",
            "receipt_path": "uploads/receipts/r7.jpg",
            "user_id": 3,
            "first_name": "Bob",
            "last_name": "Jones",
            "created_at": "2026-03-15T10:00:00Z",
            "updated_at": "2026-03-16T08:30:00Z"
        }
        """.data(using: .utf8)!

        let expense = try decoder.decode(Expense.self, from: json)

        XCTAssertEqual(expense.id, 7)
        XCTAssertEqual(expense.category, "travel")
        XCTAssertEqual(try XCTUnwrap(expense.amount), 250.00, accuracy: 0.001)
        XCTAssertEqual(expense.description, "Flight to SF")
        XCTAssertEqual(expense.date, "2026-03-15")
        XCTAssertEqual(expense.receiptPath, "uploads/receipts/r7.jpg")
        XCTAssertEqual(expense.userId, 3)
        XCTAssertEqual(expense.firstName, "Bob")
        XCTAssertEqual(expense.lastName, "Jones")
        XCTAssertEqual(expense.createdAt, "2026-03-15T10:00:00Z")
        XCTAssertEqual(expense.updatedAt, "2026-03-16T08:30:00Z")
    }

    // MARK: - createdByName computed property

    func testCreatedByNameBothParts() throws {
        let json = #"{"id":1,"first_name":"Jane","last_name":"Doe"}"#.data(using: .utf8)!
        let expense = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(expense.createdByName, "Jane Doe")
    }

    func testCreatedByNameFirstOnly() throws {
        let json = #"{"id":2,"first_name":"Solo"}"#.data(using: .utf8)!
        let expense = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(expense.createdByName, "Solo")
    }

    func testCreatedByNameNilWhenAbsent() throws {
        let json = #"{"id":3,"category":"food"}"#.data(using: .utf8)!
        let expense = try decoder.decode(Expense.self, from: json)
        XCTAssertNil(expense.createdByName)
    }

    // MARK: - Identifiable + Hashable

    func testExpenseIdentifiable() throws {
        let json = #"{"id":99,"amount":5.0}"#.data(using: .utf8)!
        let expense = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(expense.id, 99)
    }

    func testExpenseHashableEquality() throws {
        let json = #"{"id":5,"amount":10.0}"#.data(using: .utf8)!
        let a = try decoder.decode(Expense.self, from: json)
        let b = try decoder.decode(Expense.self, from: json)
        XCTAssertEqual(a, b)
    }

    // MARK: - ExpensesListResponse decode

    func testExpensesListResponseDecodes() throws {
        let json = """
        {
            "expenses": [
                {"id": 1, "category": "food", "amount": 12.50},
                {"id": 2, "category": "transport", "amount": 45.00}
            ],
            "summary": {
                "total_amount": 57.50,
                "total_count": 2
            }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ExpensesListResponse.self, from: json)

        XCTAssertEqual(response.expenses.count, 2)
        XCTAssertEqual(response.expenses[0].id, 1)
        XCTAssertEqual(response.expenses[1].category, "transport")
        let summary = try XCTUnwrap(response.summary)
        XCTAssertEqual(summary.totalAmount, 57.50, accuracy: 0.001)
        XCTAssertEqual(summary.totalCount, 2)
    }

    func testExpensesListResponseNoSummary() throws {
        let json = """
        {
            "expenses": []
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ExpensesListResponse.self, from: json)

        XCTAssertTrue(response.expenses.isEmpty)
        XCTAssertNil(response.summary)
    }

    func testExpenseDecodesNullFields() throws {
        let json = """
        {
            "id": 10,
            "category": null,
            "amount": null,
            "description": null,
            "date": null,
            "receipt_path": null,
            "user_id": null,
            "first_name": null,
            "last_name": null,
            "created_at": null,
            "updated_at": null
        }
        """.data(using: .utf8)!

        let expense = try decoder.decode(Expense.self, from: json)

        XCTAssertEqual(expense.id, 10)
        XCTAssertNil(expense.category)
        XCTAssertNil(expense.amount)
        XCTAssertNil(expense.description)
        XCTAssertNil(expense.date)
        XCTAssertNil(expense.receiptPath)
        XCTAssertNil(expense.userId)
        XCTAssertNil(expense.firstName)
        XCTAssertNil(expense.lastName)
        XCTAssertNil(expense.createdAt)
        XCTAssertNil(expense.updatedAt)
        XCTAssertNil(expense.createdByName)
    }

    // MARK: - Helpers

    /// Use default decoder (no auto-conversion). `Expense` and friends
    /// declare explicit snake_case `CodingKeys`, so they handle mapping themselves.
    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}
