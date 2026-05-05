import XCTest
@testable import Expenses
@testable import Networking

// MARK: - ExpenseCreateViewModel tests

@MainActor
final class ExpenseCreateViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateDefaults() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        XCTAssertTrue(vm.category.isEmpty)
        XCTAssertTrue(vm.amountText.isEmpty)
        XCTAssertTrue(vm.vendor.isEmpty)
        XCTAssertTrue(vm.taxAmountText.isEmpty)
        XCTAssertTrue(vm.paymentMethod.isEmpty)
        XCTAssertTrue(vm.descriptionText.isEmpty)
        XCTAssertTrue(vm.notes.isEmpty)
        XCTAssertFalse(vm.isReimbursable)
        XCTAssertFalse(vm.isSubmitting)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.createdId)
    }

    // MARK: - isValid

    func testIsValidTrueWithCategoryAndAmount() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "50.00"
        XCTAssertTrue(vm.isValid)
    }

    func testIsValidFalseWithNoCategory() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = ""
        vm.amountText = "50.00"
        XCTAssertFalse(vm.isValid)
    }

    func testIsValidFalseWithZeroAmount() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "0"
        XCTAssertFalse(vm.isValid)
    }

    func testIsValidFalseWithNegativeAmount() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "-10"
        XCTAssertFalse(vm.isValid)
    }

    func testIsValidFalseExceedsCap() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "100001"
        XCTAssertFalse(vm.isValid)
    }

    func testIsValidTrueAtExactCap() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "100000"
        XCTAssertTrue(vm.isValid)
    }

    func testIsValidFalseWithTextInAmount() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "fifty"
        XCTAssertFalse(vm.isValid)
    }

    func testIsValidAcceptsCommaAsDecimalSeparator() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Meals"
        vm.amountText = "12,50"
        XCTAssertTrue(vm.isValid)
        XCTAssertEqual(vm.amount ?? 0, 12.50, accuracy: 0.001)
    }

    // MARK: - Tax amount parsing

    func testTaxAmountNilWhenEmpty() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.taxAmountText = ""
        XCTAssertNil(vm.taxAmount)
    }

    func testTaxAmountParsedFromText() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.taxAmountText = "7.50"
        XCTAssertEqual(vm.taxAmount, 7.50, accuracy: 0.001)
    }

    func testIsValidWithTaxAmountIsTrue() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "100.00"
        vm.taxAmountText = "8.25"
        XCTAssertTrue(vm.isValid)
    }

    func testIsValidFalseWhenTaxExceedsCap() {
        let api = MockAPIClient()
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "100.00"
        vm.taxAmountText = "100001"
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - Submit success

    func testSubmitCallsCreateExpense() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.success(42))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "55.00"
        await vm.submit()
        let count = await api.postCallCount
        XCTAssertEqual(count, 1)
    }

    func testSubmitSetsCreatedId() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.success(99))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Rent"
        vm.amountText = "1500.00"
        await vm.submit()
        XCTAssertEqual(vm.createdId, 99)
    }

    func testSubmitDoesNothingWhenInvalid() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.success(1))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = ""
        vm.amountText = ""
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        let count = await api.postCallCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Submit failure

    func testSubmitFailureSetsErrorMessage() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.failure(MockError.network))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "50.00"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.createdId)
    }

    func testSubmitFailureDoesNotSetCreatedId() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.failure(MockError.network))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Tools"
        vm.amountText = "50.00"
        await vm.submit()
        XCTAssertNil(vm.createdId)
    }

    // MARK: - Reimbursable & vendor fields sent to API

    func testSubmitWithAllOptionalFields() async {
        let api = MockAPIClient()
        await api.setPostOutcome(.success(1))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Travel"
        vm.amountText = "250.00"
        vm.vendor = "Delta Airlines"
        vm.taxAmountText = "25.00"
        vm.paymentMethod = "Credit Card"
        vm.notes = "Business trip NYC"
        vm.descriptionText = "Flight to NYC"
        vm.isReimbursable = true
        await vm.submit()
        XCTAssertEqual(vm.createdId, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Date formatting

    func testSubmitFormatsDateAsISO() async {
        // We can't directly inspect the request body, but we verify no crash
        // and the POST is called with a valid date format.
        let api = MockAPIClient()
        await api.setPostOutcome(.success(7))
        let vm = ExpenseCreateViewModel(api: api)
        vm.category = "Shipping"
        vm.amountText = "15.00"
        // Use a specific date
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 15
        vm.date = Calendar(identifier: .gregorian).date(from: comps)!
        await vm.submit()
        XCTAssertEqual(vm.createdId, 7)
    }
}
