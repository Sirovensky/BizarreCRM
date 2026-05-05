import XCTest
@testable import Tickets
import Networking

// §4.1 — Unit tests for TicketExportView support logic.

// Minimal stub with a configurable base URL for export URL tests.
private actor ExportStubAPIClient: APIClient {
    private let baseURL: URL?
    init(baseURL: URL?) { self.baseURL = baseURL }
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { baseURL }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

final class TicketExportTests: XCTestCase {

    // MARK: - URL building

    func test_exportURL_buildsCorrectPath() async {
        let api = ExportStubAPIClient(baseURL: URL(string: "https://crm.example.com/api/v1")!)
        let url = await api.exportTicketsURL(filter: .all, keyword: nil, sort: .newest)
        XCTAssertNotNil(url, "Export URL must not be nil when baseURL is set")
        XCTAssertTrue(url?.path.hasSuffix("/export") == true,
                      "Export path must end with /export; got \(url?.path ?? "(nil)")")
    }

    func test_exportURL_appendsFilterQueryItem() async {
        let api = ExportStubAPIClient(baseURL: URL(string: "https://crm.example.com/api/v1")!)
        let url = await api.exportTicketsURL(filter: .open, keyword: nil, sort: .newest)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "status_group" && $0.value == "open" },
                      "Open filter must append status_group=open")
    }

    func test_exportURL_appendsKeyword() async {
        let api = ExportStubAPIClient(baseURL: URL(string: "https://crm.example.com/api/v1")!)
        let url = await api.exportTicketsURL(filter: .all, keyword: "iphone", sort: .newest)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "keyword" && $0.value == "iphone" },
                      "Keyword must appear in query items")
    }

    func test_exportURL_nilWhenNoBaseURL() async {
        let api = ExportStubAPIClient(baseURL: nil)
        let url = await api.exportTicketsURL(filter: .all, keyword: nil, sort: .newest)
        XCTAssertNil(url, "Export URL must be nil when no base URL is configured")
    }

    func test_exportURL_omitsEmptyKeyword() async {
        let api = ExportStubAPIClient(baseURL: URL(string: "https://crm.example.com/api/v1")!)
        let url = await api.exportTicketsURL(filter: .all, keyword: "", sort: .newest)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertFalse(items.contains { $0.name == "keyword" },
                       "Empty keyword must not be appended as a query item")
    }

    func test_exportURL_includesSortParam() async {
        let api = ExportStubAPIClient(baseURL: URL(string: "https://crm.example.com/api/v1")!)
        let url = await api.exportTicketsURL(filter: .all, keyword: nil, sort: .urgency)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "sort" && $0.value == "urgency" },
                      "Sort param must be included")
    }
}
