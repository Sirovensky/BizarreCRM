import XCTest
@testable import Communications
import Networking
import Core

// MARK: - SnippetEditorViewModelTests

@MainActor
final class SnippetEditorViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSnippet(
        id: Int64 = 1,
        shortcode: String = "hello",
        title: String = "Hello",
        content: String = "Hi {{first_name}}",
        category: String? = "greeting"
    ) -> Snippet {
        Snippet(id: id, shortcode: shortcode, title: title, content: content, category: category)
    }

    private func makeSUT(
        snippet: Snippet? = nil,
        saveError: Error? = nil,
        onSave: @escaping (Snippet) -> Void = { _ in }
    ) -> (SnippetEditorViewModel, SnippetEditorStubAPIClient) {
        let api = SnippetEditorStubAPIClient(saveError: saveError)
        let vm = SnippetEditorViewModel(snippet: snippet, api: api, onSave: onSave)
        return (vm, api)
    }

    // MARK: - Initial state (new)

    func test_init_newSnippet_isNewSnippetTrue() {
        let (vm, _) = makeSUT()
        XCTAssertTrue(vm.isNewSnippet)
        XCTAssertTrue(vm.shortcode.isEmpty)
        XCTAssertTrue(vm.title.isEmpty)
        XCTAssertTrue(vm.content.isEmpty)
        XCTAssertTrue(vm.category.isEmpty)
    }

    // MARK: - Initial state (edit)

    func test_init_existingSnippet_populatesFields() {
        let snip = makeSnippet()
        let (vm, _) = makeSUT(snippet: snip)
        XCTAssertFalse(vm.isNewSnippet)
        XCTAssertEqual(vm.shortcode, snip.shortcode)
        XCTAssertEqual(vm.title, snip.title)
        XCTAssertEqual(vm.content, snip.content)
        XCTAssertEqual(vm.category, snip.category)
    }

    // MARK: - Validation

    func test_isValid_falseWhenShortcodeEmpty() {
        let (vm, _) = makeSUT()
        vm.shortcode = ""
        vm.title = "Title"
        vm.content = "Content"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenTitleEmpty() {
        let (vm, _) = makeSUT()
        vm.shortcode = "sc"
        vm.title = ""
        vm.content = "Content"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenContentEmpty() {
        let (vm, _) = makeSUT()
        vm.shortcode = "sc"
        vm.title = "Title"
        vm.content = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenShortcodeHasInvalidChars() {
        let (vm, _) = makeSUT()
        vm.shortcode = "hello world"  // space is invalid
        vm.title = "Title"
        vm.content = "Content"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenShortcodeExceeds50Chars() {
        let (vm, _) = makeSUT()
        vm.shortcode = String(repeating: "a", count: 51)
        vm.title = "Title"
        vm.content = "Content"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueForValidInputs() {
        let (vm, _) = makeSUT()
        vm.shortcode = "ty-visit_1"
        vm.title = "Thank you"
        vm.content = "Thank you for visiting!"
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenTitleExceeds200Chars() {
        let (vm, _) = makeSUT()
        vm.shortcode = "sc"
        vm.title = String(repeating: "a", count: 201)
        vm.content = "Content"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenContentExceeds10000Chars() {
        let (vm, _) = makeSUT()
        vm.shortcode = "sc"
        vm.title = "Title"
        vm.content = String(repeating: "a", count: 10_001)
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - Variable extraction

    func test_extractedVariables_findsDoublebraceTokens() {
        let (vm, _) = makeSUT()
        vm.content = "Hi {{first_name}}, your ticket {{ticket_no}} is ready."
        XCTAssertEqual(vm.extractedVariables, ["{{first_name}}", "{{ticket_no}}"])
    }

    func test_extractedVariables_emptyForPlainContent() {
        let (vm, _) = makeSUT()
        vm.content = "No variables here."
        XCTAssertTrue(vm.extractedVariables.isEmpty)
    }

    // MARK: - Live preview

    func test_livePreview_substitutesKnownVariables() {
        let (vm, _) = makeSUT()
        vm.content = "Hi {{first_name}}!"
        XCTAssertEqual(vm.livePreview, "Hi Jane!")
    }

    func test_livePreview_leavesUnknownVariablesUnchanged() {
        let (vm, _) = makeSUT()
        vm.content = "Your {{unknown_var}} is here."
        XCTAssertTrue(vm.livePreview.contains("{{unknown_var}}"))
    }

    // MARK: - Save (create)

    func test_save_createSnippet_callsOnSave() async {
        var savedSnippet: Snippet?
        let (vm, _) = makeSUT(onSave: { savedSnippet = $0 })
        vm.shortcode = "ty"
        vm.title = "Thank you"
        vm.content = "Thanks for your business."
        await vm.save()
        XCTAssertNotNil(savedSnippet)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.savedSnippet)
    }

    func test_save_doesNothing_whenInvalid() async {
        var callCount = 0
        let (vm, _) = makeSUT(onSave: { _ in callCount += 1 })
        vm.shortcode = ""  // invalid
        vm.title = "Title"
        vm.content = "Content"
        await vm.save()
        XCTAssertEqual(callCount, 0)
    }

    func test_save_setsErrorMessage_onAPIFailure() async {
        let (vm, _) = makeSUT(saveError: APITransportError.httpStatus(409, message: "Shortcode already exists"))
        vm.shortcode = "dupe"
        vm.title = "Duplicate"
        vm.content = "Content here."
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_save_clearsisSaving_afterCompletion() async {
        let (vm, _) = makeSUT()
        vm.shortcode = "ty"
        vm.title = "Title"
        vm.content = "Content"
        await vm.save()
        XCTAssertFalse(vm.isSaving)
    }

    // MARK: - Save (update)

    func test_save_updateSnippet_callsOnSave() async {
        var savedSnippet: Snippet?
        let existing = makeSnippet(id: 10)
        let (vm, _) = makeSUT(snippet: existing, onSave: { savedSnippet = $0 })
        vm.title = "Updated title"
        await vm.save()
        XCTAssertNotNil(savedSnippet)
    }

    // MARK: - Category trimming

    func test_save_trimsCategoryWhitespace() async {
        var savedSnippet: Snippet?
        let (vm, api) = makeSUT(onSave: { savedSnippet = $0 })
        vm.shortcode = "sc"
        vm.title = "Title"
        vm.content = "Content"
        vm.category = "  greeting  "
        await vm.save()
        XCTAssertEqual(api.lastCreateRequest?.category, "greeting")
        _ = savedSnippet  // suppress warning
    }

    func test_save_nilsEmptyCategory() async {
        let (vm, api) = makeSUT()
        vm.shortcode = "sc"
        vm.title = "Title"
        vm.content = "Content"
        vm.category = "   "
        await vm.save()
        XCTAssertNil(api.lastCreateRequest?.category)
    }
}

// MARK: - SnippetEditorStubAPIClient

final class SnippetEditorStubAPIClient: APIClient, @unchecked Sendable {
    let saveError: Error?
    private(set) var lastCreateRequest: CreateSnippetRequest?

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = saveError { throw err }
        if let req = body as? CreateSnippetRequest {
            lastCreateRequest = req
            let snip = Snippet(id: 1, shortcode: req.shortcode, title: req.title, content: req.content, category: req.category)
            guard let result = snip as? T else { throw APITransportError.decoding("type") }
            return result
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = saveError { throw err }
        let snip = Snippet(id: 10, shortcode: "sc", title: "Updated", content: "Content")
        guard let result = snip as? T else { throw APITransportError.decoding("type") }
        return result
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
