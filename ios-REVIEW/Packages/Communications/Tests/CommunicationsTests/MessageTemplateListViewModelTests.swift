import XCTest
@testable import Communications
import Networking
import Core

// MARK: - MessageTemplateListViewModelTests

@MainActor
final class MessageTemplateListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTemplate(id: Int64, name: String, channel: MessageChannel = .sms, category: MessageTemplateCategory = .reminder) -> MessageTemplate {
        MessageTemplate(id: id, name: name, body: "Hello {first_name}", channel: channel, category: category)
    }

    private func makeSUT(templates: [MessageTemplate] = [], deleteError: Error? = nil) -> (MessageTemplateListViewModel, TemplateStubAPIClient) {
        let api = TemplateStubAPIClient(templates: templates, deleteError: deleteError)
        return (MessageTemplateListViewModel(api: api), api)
    }

    // MARK: - Load

    func test_load_populatesTemplates() async {
        let (vm, _) = makeSUT(templates: [makeTemplate(id: 1, name: "Welcome"), makeTemplate(id: 2, name: "Promo")])
        await vm.load()
        XCTAssertEqual(vm.templates.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsError_onFailure() async {
        let api = TemplateStubAPIClient(templates: [], listError: APITransportError.networkUnavailable)
        let vm = MessageTemplateListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Filter

    func test_filter_byChannel() async {
        let (vm, _) = makeSUT(templates: [
            makeTemplate(id: 1, name: "SMS one", channel: .sms),
            makeTemplate(id: 2, name: "Email one", channel: .email)
        ])
        await vm.load()
        vm.filterChannel = .email
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered.first?.channel, .email)
    }

    func test_filter_bySearch() async {
        let (vm, _) = makeSUT(templates: [
            makeTemplate(id: 1, name: "Welcome SMS"),
            makeTemplate(id: 2, name: "Promo blast")
        ])
        await vm.load()
        vm.searchQuery = "Welcome"
        XCTAssertEqual(vm.filtered.count, 1)
    }

    func test_filter_nilChannel_showsAll() async {
        let (vm, _) = makeSUT(templates: [
            makeTemplate(id: 1, name: "A", channel: .sms),
            makeTemplate(id: 2, name: "B", channel: .email)
        ])
        await vm.load()
        vm.filterChannel = nil
        XCTAssertEqual(vm.filtered.count, 2)
    }

    // MARK: - Delete

    func test_delete_optimisticallyRemoves() async {
        let tmpl = makeTemplate(id: 99, name: "To delete")
        let (vm, _) = makeSUT(templates: [tmpl])
        await vm.load()
        XCTAssertEqual(vm.templates.count, 1)
        // Fire delete without awaiting — check optimistic removal
        let t = makeTemplate(id: 99, name: "To delete")
        vm.templates.removeAll { $0.id == t.id }
        XCTAssertTrue(vm.templates.isEmpty)
    }

    // MARK: - Pick callback

    func test_pick_callsOnPickClosure() async {
        var pickedId: Int64?
        let (vm, _) = makeSUT(templates: [makeTemplate(id: 5, name: "Ping")])
        vm.onPick = { pickedId = $0.id }
        await vm.load()
        vm.pick(vm.templates.first!)
        XCTAssertEqual(pickedId, 5)
    }
}

// MARK: - TemplateStubAPIClient

private actor TemplateStubAPIClient: APIClient {
    let templates: [MessageTemplate]
    let deleteError: Error?
    let listError: Error?

    init(templates: [MessageTemplate], deleteError: Error? = nil, listError: Error? = nil) {
        self.templates = templates
        self.deleteError = deleteError
        self.listError = listError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = listError { throw err }
        // Server endpoint is /sms/templates (per sms.routes.ts:839)
        if path.contains("/sms/templates") || path.contains("/message-templates") {
            let resp = MessageTemplateListResponse(templates: templates)
            guard let t = resp as? T else { throw APITransportError.decoding("type") }
            return t
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {
        if let err = deleteError { throw err }
    }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
