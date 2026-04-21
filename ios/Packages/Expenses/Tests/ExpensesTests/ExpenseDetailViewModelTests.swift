import XCTest
@testable import Expenses
@testable import Networking

// MARK: - Inline mock API client

/// A minimal `APIClient` conformance for testing. Only `getExpense` is
/// wired; all other protocol requirements throw an assertion failure so tests
/// surface unexpected calls immediately.
actor MockAPIClient: APIClient {
    enum Outcome {
        case success(Expense)
        case failure(Error)
    }

    var getExpenseOutcome: Outcome = .failure(MockError.notConfigured)
    private(set) var getExpenseCallCount: Int = 0

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasPrefix("/api/v1/expenses/"), T.self == Expense.self {
            getExpenseCallCount += 1
            switch getExpenseOutcome {
            case .success(let e):
                guard let typed = e as? T else { throw MockError.typeMismatch }
                return typed
            case .failure(let err):
                throw err
            }
        }
        throw MockError.notConfigured
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured
    }

    func delete(_ path: String) async throws {
        throw MockError.notConfigured
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw MockError.notConfigured
    }

    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) {}
}

enum MockError: Error, LocalizedError {
    case notConfigured
    case typeMismatch
    case network

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Mock not configured"
        case .typeMismatch:  return "Type mismatch in mock"
        case .network:       return "Simulated network error"
        }
    }
}

// MARK: - Test fixtures

extension Expense {
    static func fixture(
        id: Int64 = 1,
        category: String? = "office",
        amount: Double? = 42.50,
        description: String? = "Desk lamp",
        date: String? = "2026-03-01",
        receiptPath: String? = nil,
        userId: Int64? = 5,
        firstName: String? = "Alice",
        lastName: String? = "Smith",
        createdAt: String? = "2026-03-01T09:00:00Z",
        updatedAt: String? = nil
    ) -> Expense {
        // Build via JSON round-trip. Use a plain JSONDecoder so that the
        // struct's explicit snake_case CodingKeys are matched against the
        // literal JSON keys (no auto-conversion interfering).
        var dict: [String: Any] = ["id": id]
        if let category   { dict["category"]     = category }
        if let amount     { dict["amount"]        = amount }
        if let description { dict["description"]  = description }
        if let date       { dict["date"]          = date }
        if let receiptPath { dict["receipt_path"] = receiptPath }
        if let userId     { dict["user_id"]       = userId }
        if let firstName  { dict["first_name"]    = firstName }
        if let lastName   { dict["last_name"]     = lastName }
        if let createdAt  { dict["created_at"]    = createdAt }
        if let updatedAt  { dict["updated_at"]    = updatedAt }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Expense.self, from: data)
    }
}

// MARK: - ViewModel state machine tests

@MainActor
final class ExpenseDetailViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsLoading() {
        let api = MockAPIClient()
        let vm = ExpenseDetailViewModel(api: api, id: 1)

        if case .loading = vm.state {
            // Correct — initial state is loading.
        } else {
            XCTFail("Expected .loading, got \(vm.state)")
        }
    }

    // MARK: - Successful load

    func testLoadTransitionsToLoaded() async {
        let api = MockAPIClient()
        let expense = Expense.fixture(id: 1, category: "food", amount: 15.00)
        await api.setOutcome(.success(expense))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .loaded(let result) = vm.state else {
            return XCTFail("Expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(result.id, 1)
        XCTAssertEqual(result.category, "food")
        XCTAssertEqual(try XCTUnwrap(result.amount), 15.00, accuracy: 0.001)
    }

    // MARK: - Failed load

    func testLoadTransitionsToFailed() async {
        let api = MockAPIClient()
        await api.setOutcome(.failure(MockError.network))

        let vm = ExpenseDetailViewModel(api: api, id: 99)
        await vm.load()

        guard case .failed(let msg) = vm.state else {
            return XCTFail("Expected .failed, got \(vm.state)")
        }
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - Reload preserves stale state while in flight

    func testSoftRefreshKeepsLoadedState() async {
        let api = MockAPIClient()
        let expense = Expense.fixture(id: 5, category: "travel", amount: 300.00)
        await api.setOutcome(.success(expense))

        let vm = ExpenseDetailViewModel(api: api, id: 5)
        // First load.
        await vm.load()

        // Verify we're loaded, then verify state doesn't reset to .loading on second call.
        guard case .loaded = vm.state else {
            return XCTFail("Expected .loaded after first load")
        }

        // Second load — state stays .loaded during the call (soft refresh).
        await vm.load()

        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded to be preserved during soft refresh")
            return
        }
    }

    // MARK: - Call count

    func testLoadCallsAPIOnce() async {
        let api = MockAPIClient()
        await api.setOutcome(.success(Expense.fixture()))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        let count = await api.getExpenseCallCount
        XCTAssertEqual(count, 1)
    }

    func testReloadCallsAPITwice() async {
        let api = MockAPIClient()
        await api.setOutcome(.success(Expense.fixture()))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()
        await vm.load()

        let count = await api.getExpenseCallCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Error message content

    func testFailedStateContainsLocalizedDescription() async {
        let api = MockAPIClient()
        await api.setOutcome(.failure(MockError.network))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .failed(let msg) = vm.state else {
            return XCTFail("Expected .failed")
        }
        XCTAssertEqual(msg, MockError.network.localizedDescription)
    }

    // MARK: - Receipt path

    func testLoadedExpenseExposesReceiptPath() async {
        let api = MockAPIClient()
        let expense = Expense.fixture(receiptPath: "uploads/r1.jpg")
        await api.setOutcome(.success(expense))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .loaded(let result) = vm.state else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertEqual(result.receiptPath, "uploads/r1.jpg")
    }

    // MARK: - User name

    func testLoadedExpenseExposesCreatedByName() async {
        let api = MockAPIClient()
        let expense = Expense.fixture(firstName: "Jane", lastName: "Doe")
        await api.setOutcome(.success(expense))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .loaded(let result) = vm.state else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertEqual(result.createdByName, "Jane Doe")
    }

    // MARK: - No receipt path

    func testLoadedExpenseWithNoReceiptPath() async {
        let api = MockAPIClient()
        let expense = Expense.fixture(receiptPath: nil)
        await api.setOutcome(.success(expense))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .loaded(let result) = vm.state else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertNil(result.receiptPath)
    }

    // MARK: - Recovery from failure

    func testCanRecoverAfterFailure() async {
        let api = MockAPIClient()
        await api.setOutcome(.failure(MockError.network))

        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()

        guard case .failed = vm.state else {
            return XCTFail("Expected .failed")
        }

        // Now succeed.
        await api.setOutcome(.success(Expense.fixture()))
        await vm.load()

        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after recovery")
            return
        }
    }
}

// MARK: - MockAPIClient helper

extension MockAPIClient {
    func setOutcome(_ outcome: Outcome) {
        getExpenseOutcome = outcome
    }
}
