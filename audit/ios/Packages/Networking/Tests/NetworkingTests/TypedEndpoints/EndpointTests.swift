import XCTest
@testable import Networking

/// Tests for the Endpoint protocol, TypedEndpoint, and EndpointError.
/// Coverage: HTTPMethod, Endpoint.build(baseURL:), EndpointError.
final class EndpointTests: XCTestCase {

    private let base = URL(string: "https://shop.bizarrecrm.com")!

    // MARK: - HTTPMethod

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue,    "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue,   "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue,    "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue,  "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    func testHTTPMethodEquality() {
        XCTAssertEqual(HTTPMethod.get, HTTPMethod.get)
        XCTAssertNotEqual(HTTPMethod.get, HTTPMethod.post)
    }

    // MARK: - build(baseURL:) — basic cases

    func testBuildProducesCorrectURL() throws {
        let ep = Endpoints.Tickets.list()
        let request = try ep.build(baseURL: base)
        XCTAssertEqual(request.url?.path, "/api/v1/tickets")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testBuildPreservesMethod() throws {
        let ep = Endpoints.Tickets.create()
        let request = try ep.build(baseURL: base)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testBuildWithQueryItems() throws {
        let ep = Endpoints.Tickets.list(statusGroup: "open", keyword: "mac", pageSize: 25)
        let request = try ep.build(baseURL: base)
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let items = components.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["status_group"], "open")
        XCTAssertEqual(dict["keyword"], "mac")
        XCTAssertEqual(dict["pagesize"], "25")
    }

    func testBuildWithNoQueryItemsProducesCleanURL() throws {
        let ep = Endpoints.Tickets.list()
        let request = try ep.build(baseURL: base)
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        XCTAssertNil(components.queryItems)
    }

    func testBuildInterpolatesIDInPath() throws {
        let ep = Endpoints.Tickets.detail(id: 42)
        let request = try ep.build(baseURL: base)
        XCTAssertEqual(request.url?.path, "/api/v1/tickets/42")
    }

    // MARK: - EndpointError

    func testEndpointErrorEquality() {
        let a = EndpointError.invalidURL(path: "/p", base: "http://x.com")
        let b = EndpointError.invalidURL(path: "/p", base: "http://x.com")
        let c = EndpointError.invalidURL(path: "/q", base: "http://x.com")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
