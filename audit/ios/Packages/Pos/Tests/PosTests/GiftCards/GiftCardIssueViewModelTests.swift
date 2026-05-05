#if canImport(UIKit)
import XCTest
@testable import Pos
@testable import Networking

/// Tests for ``GiftCardIssueViewModel``.
///
/// The API is stubbed via `MockIssueAPIClient` — no network required.
@MainActor
final class GiftCardIssueViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAPI(
        issueResult: Result<IssueGiftCardResponse, Error>? = nil
    ) -> MockIssueAPIClient {
        MockIssueAPIClient(issueResult: issueResult)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initial_amountInput_isEmpty() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        XCTAssertEqual(vm.amountInput, "")
    }

    // MARK: - Validation

    func test_validationError_zeroAmount() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "0"
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_emptyInput() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = ""
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_overMax() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = String(GiftCardIssueViewModel.maxAmountCents + 1)
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_exactlyAtMax_isValid() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = String(GiftCardIssueViewModel.maxAmountCents)
        XCTAssertNil(vm.validationError)
    }

    func test_validationError_positiveAmount_isValid() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "5000"
        XCTAssertNil(vm.validationError)
    }

    func test_validationError_invalidEmail() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "5000"
        vm.recipientEmail = "not-an-email"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("email"))
    }

    func test_validationError_validEmail_isNil() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "5000"
        vm.recipientEmail = "alice@example.com"
        XCTAssertNil(vm.validationError)
    }

    // MARK: - canIssue

    func test_canIssue_false_whenAmountZero() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "0"
        XCTAssertFalse(vm.canIssue)
    }

    func test_canIssue_true_whenAmountPositive() {
        let vm = GiftCardIssueViewModel(api: makeAPI())
        vm.amountInput = "1000"
        XCTAssertTrue(vm.canIssue)
    }

    // MARK: - issue()

    func test_issue_success_setsIssuedState() async {
        let response = IssueGiftCardResponse(id: 42, code: "ABCD1234ABCD1234")
        let api = makeAPI(issueResult: .success(response))
        let vm = GiftCardIssueViewModel(api: api)
        vm.amountInput = "5000"
        await vm.issue()
        if case .issued(let code, let balanceCents) = vm.state {
            XCTAssertEqual(code, "ABCD1234ABCD1234")
            XCTAssertEqual(balanceCents, 5000)
        } else {
            XCTFail("Expected .issued, got \(vm.state)")
        }
    }

    func test_issue_failure_setsFailureState() async {
        let api = makeAPI(issueResult: .failure(MockAPIError()))
        let vm = GiftCardIssueViewModel(api: api)
        vm.amountInput = "5000"
        await vm.issue()
        if case .failure = vm.state { /* pass */ }
        else { XCTFail("Expected .failure, got \(vm.state)") }
    }

    func test_issue_invalidAmount_doesNotCallAPI() async {
        let api = makeAPI(issueResult: .success(IssueGiftCardResponse(id: 1, code: "X")))
        let vm = GiftCardIssueViewModel(api: api)
        vm.amountInput = "0"
        await vm.issue()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(api.issueCalled)
    }

    func test_issue_withOptionalFields_passesThrough() async {
        let response = IssueGiftCardResponse(id: 10, code: "TESTCODE")
        let api = makeAPI(issueResult: .success(response))
        let vm = GiftCardIssueViewModel(api: api)
        vm.amountInput = "2000"
        vm.recipientName = "Bob"
        vm.recipientEmail = "bob@example.com"
        vm.notes = "Birthday gift"
        await vm.issue()
        if case .issued(let code, _) = vm.state {
            XCTAssertEqual(code, "TESTCODE")
        } else {
            XCTFail("Expected .issued, got \(vm.state)")
        }
    }

    // MARK: - reset()

    func test_reset_clearsAllFields() async {
        let response = IssueGiftCardResponse(id: 1, code: "RESETCODE")
        let api = makeAPI(issueResult: .success(response))
        let vm = GiftCardIssueViewModel(api: api)
        vm.amountInput = "3000"
        vm.recipientName = "Alice"
        vm.recipientEmail = "alice@example.com"
        vm.notes = "Test"
        await vm.issue()
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.amountInput, "")
        XCTAssertEqual(vm.recipientName, "")
        XCTAssertEqual(vm.recipientEmail, "")
        XCTAssertEqual(vm.notes, "")
    }
}

// MARK: - MockIssueAPIClient

/// Minimal mock for `GiftCardIssueViewModelTests`.
/// Stubs `issueGiftCard`; all other calls throw `URLError(.badURL)`.
final class MockIssueAPIClient: APIClient, @unchecked Sendable {
    var issueResult: Result<IssueGiftCardResponse, Error>?
    private(set) var issueCalled = false

    init(issueResult: Result<IssueGiftCardResponse, Error>? = nil) {
        self.issueResult = issueResult
    }

    func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        if path == "/api/v1/gift-cards" {
            issueCalled = true
            guard let result = issueResult else { throw MockAPIError() }
            return try result.get() as! T
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.badURL) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}

}
#endif
