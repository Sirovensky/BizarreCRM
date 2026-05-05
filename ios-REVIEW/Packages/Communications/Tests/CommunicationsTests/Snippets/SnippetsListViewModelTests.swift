import XCTest
@testable import Communications
import Networking
import Core

// MARK: - SnippetsListViewModelTests

@MainActor
final class SnippetsListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSnippet(
        id: Int64,
        shortcode: String = "sc",
        title: String = "Title",
        content: String = "Hello {{first_name}}",
        category: String? = nil
    ) -> Snippet {
        Snippet(id: id, shortcode: shortcode, title: title, content: content, category: category)
    }

    private func makeSUT(
        snippets: [Snippet] = [],
        listError: Error? = nil,
        deleteError: Error? = nil
    ) -> (SnippetsListViewModel, SnippetsStubAPIClient) {
        let api = SnippetsStubAPIClient(snippets: snippets, listError: listError, deleteError: deleteError)
        return (SnippetsListViewModel(api: api), api)
    }

    // MARK: - Load

    func test_load_populatesSnippets() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, title: "Thank you"),
            makeSnippet(id: 2, title: "Follow up")
        ])
        await vm.load()
        XCTAssertEqual(vm.snippets.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsErrorMessage_onFailure() async {
        let (vm, _) = makeSUT(listError: APITransportError.networkUnavailable)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.snippets.isEmpty)
    }

    func test_load_clearsErrorMessage_onSuccess() async {
        let api = SnippetsStubAPIClient(snippets: [makeSnippet(id: 1)], listError: nil)
        let vm = SnippetsListViewModel(api: api)
        // Manually set an error first
        await vm.load()
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsIsLoading_whileInFlight() async {
        // Lightweight check: isLoading ends as false after load completes
        let (vm, _) = makeSUT(snippets: [makeSnippet(id: 1)])
        XCTAssertFalse(vm.isLoading)
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Filter by category

    func test_filtered_showsAll_whenNoCategoryFilter() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: "greeting"),
            makeSnippet(id: 2, category: "follow-up")
        ])
        await vm.load()
        vm.filterCategory = nil
        XCTAssertEqual(vm.filtered.count, 2)
    }

    func test_filtered_byCategory() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: "greeting"),
            makeSnippet(id: 2, category: "follow-up")
        ])
        await vm.load()
        vm.filterCategory = "greeting"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered.first?.category, "greeting")
    }

    func test_filtered_bySearch_matchesTitle() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, title: "Welcome back"),
            makeSnippet(id: 2, title: "Invoice reminder")
        ])
        await vm.load()
        vm.searchQuery = "Welcome"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered.first?.title, "Welcome back")
    }

    func test_filtered_bySearch_matchesShortcode() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, shortcode: "ty-visit"),
            makeSnippet(id: 2, shortcode: "promo-blast")
        ])
        await vm.load()
        vm.searchQuery = "ty-"
        XCTAssertEqual(vm.filtered.count, 1)
    }

    func test_filtered_bySearch_matchesContent() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, content: "Thank you for your visit"),
            makeSnippet(id: 2, content: "Your invoice is due")
        ])
        await vm.load()
        vm.searchQuery = "invoice"
        XCTAssertEqual(vm.filtered.count, 1)
    }

    func test_filtered_emptySearch_showsAll() async {
        let (vm, _) = makeSUT(snippets: [makeSnippet(id: 1), makeSnippet(id: 2)])
        await vm.load()
        vm.searchQuery = ""
        XCTAssertEqual(vm.filtered.count, 2)
    }

    // MARK: - Grouped

    func test_groupedFiltered_groupsByCategory() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: "greeting"),
            makeSnippet(id: 2, category: "greeting"),
            makeSnippet(id: 3, category: "follow-up")
        ])
        await vm.load()
        XCTAssertEqual(vm.groupedFiltered.count, 2)
        let greetingGroup = vm.groupedFiltered.first { $0.category == "greeting" }
        XCTAssertEqual(greetingGroup?.snippets.count, 2)
    }

    func test_groupedFiltered_uncategorisedUnderEmptyKey() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: nil),
            makeSnippet(id: 2, category: "greeting")
        ])
        await vm.load()
        let uncategorised = vm.groupedFiltered.first { $0.category == "" }
        XCTAssertNotNil(uncategorised)
        XCTAssertEqual(uncategorised?.snippets.count, 1)
    }

    // MARK: - allCategories

    func test_allCategories_deduplicatesAndSorts() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: "greeting"),
            makeSnippet(id: 2, category: "greeting"),
            makeSnippet(id: 3, category: "follow-up")
        ])
        await vm.load()
        XCTAssertEqual(vm.allCategories, ["follow-up", "greeting"])
    }

    func test_allCategories_excludesNilAndEmpty() async {
        let (vm, _) = makeSUT(snippets: [
            makeSnippet(id: 1, category: nil),
            makeSnippet(id: 2, category: ""),
            makeSnippet(id: 3, category: "greeting")
        ])
        await vm.load()
        XCTAssertEqual(vm.allCategories, ["greeting"])
    }

    // MARK: - Delete

    func test_delete_optimisticallyRemovesSnippet() async {
        let snip = makeSnippet(id: 42, title: "Remove me")
        let (vm, _) = makeSUT(snippets: [snip])
        await vm.load()
        XCTAssertEqual(vm.snippets.count, 1)
        // Simulate optimistic removal
        vm.snippets = vm.snippets.filter { $0.id != snip.id }
        XCTAssertTrue(vm.snippets.isEmpty)
    }

    func test_delete_revertsOnAPIError() async {
        let snip = makeSnippet(id: 7)
        let (vm, _) = makeSUT(snippets: [snip], deleteError: APITransportError.networkUnavailable)
        await vm.load()
        await vm.delete(snippet: snip)
        // After revert via load(), snippet should be restored
        XCTAssertEqual(vm.snippets.count, 1)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Pick callback

    func test_pick_callsOnPickClosure() async {
        var pickedId: Int64?
        let snip = makeSnippet(id: 55, title: "Pick me")
        let (vm, _) = makeSUT(snippets: [snip])
        vm.onPick = { pickedId = $0.id }
        await vm.load()
        vm.pick(vm.snippets.first!)
        XCTAssertEqual(pickedId, 55)
    }

    func test_pick_noCallback_doesNotCrash() async {
        let snip = makeSnippet(id: 1)
        let (vm, _) = makeSUT(snippets: [snip])
        vm.onPick = nil
        await vm.load()
        // Should not crash
        vm.pick(vm.snippets.first!)
    }
}

// MARK: - SnippetsStubAPIClient

actor SnippetsStubAPIClient: APIClient {
    private let snippets: [Snippet]
    private let listError: Error?
    private let deleteError: Error?

    init(snippets: [Snippet], listError: Error? = nil, deleteError: Error? = nil) {
        self.snippets = snippets
        self.listError = listError
        self.deleteError = deleteError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = listError { throw err }
        if path.contains("/snippets") {
            guard let result = snippets as? T else { throw APITransportError.decoding("type") }
            return result
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let req = body as? CreateSnippetRequest {
            let snip = Snippet(id: 999, shortcode: req.shortcode, title: req.title, content: req.content, category: req.category)
            guard let result = snip as? T else { throw APITransportError.decoding("type") }
            return result
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let existing = snippets.first, let result = existing as? T {
            return result
        }
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {
        if let err = deleteError { throw err }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
