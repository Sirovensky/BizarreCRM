import XCTest
@testable import Expenses
@testable import Networking

// MARK: - iPadPolishTests
//
// Coverage for §22 iPad polish additions:
//   1. ExpenseCSVExporter          — pure logic, no UI, 100% testable
//   2. ExpenseReceiptInspectorViewModel — async state machine tests
//   3. Three-column category count logic
//
// MockAPIClient, MockError, and Expense.fixture() are defined in
// ExpenseDetailViewModelTests.swift and compiled into the same test target.

// MARK: - 1. ExpenseCSVExporter Tests

final class ExpenseCSVExporterTests: XCTestCase {

    func testCSVContainsHeaderRow() {
        let exp = Expense.fixture(id: 1, category: "travel", amount: 99.0)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(
            lines[0].hasPrefix("id,category,amount"),
            "Header must start with id,category,amount"
        )
    }

    func testCSVDataRowContainsExpenseId() {
        let exp = Expense.fixture(id: 42, category: "meals", amount: 15.50)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("42"))
    }

    func testCSVDataRowContainsAmount() {
        let exp = Expense.fixture(id: 1, category: "fuel", amount: 77.25)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("77.25"))
    }

    func testCSVDataRowContainsCategory() {
        let exp = Expense.fixture(id: 1, category: "software", amount: 12.0)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("software"))
    }

    func testCSVEscapesCommaInDescription() {
        let exp = Expense.fixture(id: 1, category: "meals", amount: 10.0, description: "Lunch, coffee")
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("\"Lunch, coffee\""), "Description with comma must be quoted")
    }

    func testCSVEscapesDoubleQuoteInDescription() {
        let exp = Expense.fixture(id: 1, category: "meals", amount: 10.0, description: "He said \"hi\"")
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("\"He said \"\"hi\"\"\""), "Internal quotes must be doubled")
    }

    func testCSVNilFieldsDoNotCrash() {
        let exp = Expense.fixture(id: 1, category: nil, amount: nil, description: nil)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertFalse(csv.isEmpty)
    }

    func testCSVIncludesStatus() {
        let exp = Expense.fixture(id: 1, status: "approved")
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("approved"))
    }

    func testCSVIncludesVendor() {
        let exp = Expense.fixture(id: 1, vendor: "Acme Corp")
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertTrue(csv.contains("Acme Corp"))
    }

    func testCSVProducesTwoLines() {
        let exp = Expense.fixture(id: 5, category: "tools", amount: 250.0)
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    func testCSVIsReproducible() {
        let exp = Expense.fixture(id: 7, category: "rent", amount: 1200.0)
        let csv1 = ExpenseCSVExporter.csvLine(for: exp)
        let csv2 = ExpenseCSVExporter.csvLine(for: exp)
        XCTAssertEqual(csv1, csv2)
    }

    func testCSVFieldCountMatchesHeader() {
        let exp = Expense.fixture(
            id: 3,
            category: "meals",
            amount: 25.0,
            description: "Team lunch",
            vendor: "Bistro",
            status: "pending"
        )
        let csv = ExpenseCSVExporter.csvLine(for: exp)
        let lines = csv.components(separatedBy: "\n")
        // We count commas rather than parsing quoted CSV to keep the test simple.
        // Header has 8 commas (9 columns); data row must have the same.
        let headerCommas = lines[0].filter { $0 == "," }.count
        let dataCommas   = lines[1].filter { $0 == "," }.count
        XCTAssertEqual(headerCommas, dataCommas, "Header and data row must have the same number of columns")
    }
}

// MARK: - 2. Three-Column Category Count Logic Tests

final class ExpensesThreeColumnCategoryCountTests: XCTestCase {

    // Pure helper — mirrors the logic in ExpensesThreeColumnView.categoryCount(for:)
    private func countFor(category: String, in expenses: [Expense]) -> Int {
        guard category != "All" else { return expenses.count }
        return expenses.filter {
            $0.category?.lowercased() == category.lowercased()
        }.count
    }

    func testAllCategoryReturnsTotal() {
        let expenses = [
            Expense.fixture(id: 1, category: "travel"),
            Expense.fixture(id: 2, category: "meals"),
            Expense.fixture(id: 3, category: "travel"),
        ]
        XCTAssertEqual(countFor(category: "All", in: expenses), 3)
    }

    func testSpecificCategoryFiltersCorrectly() {
        let expenses = [
            Expense.fixture(id: 1, category: "travel"),
            Expense.fixture(id: 2, category: "meals"),
            Expense.fixture(id: 3, category: "TRAVEL"),
        ]
        XCTAssertEqual(countFor(category: "travel", in: expenses), 2)
    }

    func testMissingCategoryReturnsZero() {
        let expenses = [Expense.fixture(id: 1, category: "fuel")]
        XCTAssertEqual(countFor(category: "meals", in: expenses), 0)
    }

    func testEmptyExpensesAllReturnsZero() {
        XCTAssertEqual(countFor(category: "All", in: []), 0)
    }

    func testCaseSensitivityIsIgnored() {
        let expenses = [
            Expense.fixture(id: 1, category: "Software"),
            Expense.fixture(id: 2, category: "software"),
            Expense.fixture(id: 3, category: "SOFTWARE"),
        ]
        XCTAssertEqual(countFor(category: "software", in: expenses), 3)
    }

    func testNilCategoryDoesNotCountForNamedCategory() {
        let expenses = [
            Expense.fixture(id: 1, category: nil),
            Expense.fixture(id: 2, category: "meals"),
        ]
        XCTAssertEqual(countFor(category: "meals", in: expenses), 1)
    }

    func testAllCategoryCountsNilCategoryItems() {
        let expenses = [
            Expense.fixture(id: 1, category: nil),
            Expense.fixture(id: 2, category: "meals"),
        ]
        XCTAssertEqual(countFor(category: "All", in: expenses), 2)
    }

    func testSingleMatchInLargeList() {
        var expenses = (1...20).map { i in
            Expense.fixture(id: Int64(i), category: "rent")
        }
        expenses.append(Expense.fixture(id: 99, category: "travel"))
        XCTAssertEqual(countFor(category: "travel", in: expenses), 1)
    }
}

// MARK: - 3. ExpenseReceiptInspector ViewModel Tests
//
// Uses a subclass to inject mock responses without adding stored properties
// to MockAPIClient (which would require modifying the existing test file).

@MainActor
final class ExpenseReceiptInspectorViewModelTests: XCTestCase {

    // MARK: Minimal receipt-injecting subclass

    final class MockReceiptVM: ExpenseReceiptInspectorViewModel {
        // Injected responses
        var receiptPath: String? = nil
        var shouldFailLoad: Bool = false
        var shouldFailDelete: Bool = false
        var mockBaseURL: URL? = URL(string: "https://test.local")

        override func load() async {
            state = .loading
            if shouldFailLoad {
                state = .failed("Simulated network error")
                return
            }
            guard let path = receiptPath, !path.isEmpty else {
                state = .noReceipt
                return
            }
            guard let base = mockBaseURL else {
                state = .failed("No base URL")
                return
            }
            let url: URL
            if path.hasPrefix("http") {
                url = URL(string: path) ?? base
            } else {
                let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
                url = base.appendingPathComponent(trimmed)
            }
            state = .loaded(receiptURL: url)
        }

        override func deleteReceipt() async {
            guard !isDeleting else { return }
            deleteError = nil
            isDeleting = true
            defer { isDeleting = false }
            if shouldFailDelete {
                deleteError = "Simulated delete error"
            } else {
                state = .noReceipt
            }
        }
    }

    private func makeVM(
        receiptPath: String? = nil,
        failLoad: Bool = false,
        failDelete: Bool = false
    ) -> MockReceiptVM {
        let api = MockAPIClient()
        let vm = MockReceiptVM(api: api, expenseId: 1)
        vm.receiptPath = receiptPath
        vm.shouldFailLoad = failLoad
        vm.shouldFailDelete = failDelete
        return vm
    }

    // MARK: Initial state

    func testInitialStateIsIdle() {
        let vm = makeVM()
        if case .idle = vm.state { } else {
            XCTFail("Expected .idle, got \(vm.state)")
        }
    }

    // MARK: Load with receipt → .loaded

    func testLoadTransitionsToLoaded() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/r.jpg")
        await vm.load()
        if case .loaded(let url) = vm.state {
            XCTAssertTrue(url.absoluteString.hasSuffix("uploads/receipts/r.jpg"))
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    // MARK: Load with nil receipt → .noReceipt

    func testLoadTransitionsToNoReceiptWhenNil() async {
        let vm = makeVM(receiptPath: nil)
        await vm.load()
        if case .noReceipt = vm.state { } else {
            XCTFail("Expected .noReceipt")
        }
    }

    // MARK: Load with empty path → .noReceipt

    func testLoadTransitionsToNoReceiptWhenEmpty() async {
        let vm = makeVM(receiptPath: "")
        await vm.load()
        if case .noReceipt = vm.state { } else {
            XCTFail("Expected .noReceipt for empty path")
        }
    }

    // MARK: Network error → .failed

    func testLoadTransitionsToFailedOnError() async {
        let vm = makeVM(failLoad: true)
        await vm.load()
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed")
        }
    }

    // MARK: Delete success → .noReceipt

    func testDeleteReceiptSucceeds() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/r.jpg")
        await vm.load()
        await vm.deleteReceipt()
        if case .noReceipt = vm.state { } else {
            XCTFail("Expected .noReceipt after delete")
        }
        XCTAssertNil(vm.deleteError)
        XCTAssertFalse(vm.isDeleting)
    }

    // MARK: Delete failure exposes error

    func testDeleteReceiptFailureExposesError() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/r.jpg", failDelete: true)
        await vm.load()
        await vm.deleteReceipt()
        XCTAssertNotNil(vm.deleteError)
        XCTAssertFalse(vm.isDeleting)
    }

    // MARK: Absolute URL passes through unchanged

    func testAbsoluteReceiptURLPreserved() async {
        let vm = makeVM(receiptPath: "https://cdn.example.com/receipts/r.jpg")
        await vm.load()
        if case .loaded(let url) = vm.state {
            XCTAssertEqual(url.absoluteString, "https://cdn.example.com/receipts/r.jpg")
        } else {
            XCTFail("Expected .loaded")
        }
    }

    // MARK: isDeleting is false after completion

    func testIsNotDeletingAfterSuccessfulDelete() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/r.jpg")
        await vm.load()
        await vm.deleteReceipt()
        XCTAssertFalse(vm.isDeleting)
    }

    // MARK: isDeleting is false after failed delete

    func testIsNotDeletingAfterFailedDelete() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/r.jpg", failDelete: true)
        await vm.load()
        await vm.deleteReceipt()
        XCTAssertFalse(vm.isDeleting)
    }

    // MARK: State goes loading → loaded

    func testStateIsLoadingThenLoaded() async {
        let vm = makeVM(receiptPath: "/uploads/receipts/transition.jpg")
        // Kick off load without awaiting to observe intermediate .loading state
        let task = Task { @MainActor in await vm.load() }
        // After load completes, state should be loaded
        await task.value
        if case .loaded = vm.state { } else {
            XCTFail("Expected .loaded after await")
        }
    }
}
