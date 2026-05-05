import Foundation
import XCTest

// MARK: - §31.1 NetworkMockBuilder — fluent test-only HTTP stub builder
//
// Wraps MockURLProtocol in a declarative API so test setUp becomes readable:
//
//   let session = NetworkMockBuilder()
//       .stub("GET", path: "/api/v1/tickets", json: ticketsJSON)
//       .stub("POST", path: "/api/v1/tickets", statusCode: 201, json: createdJSON)
//       .stub("DELETE", path: "/api/v1/tickets/1", statusCode: 204)
//       .buildSession()
//
// The builder installs a single `MockURLProtocol.requestHandler` that matches
// stubs in registration order. Unmatched requests fail the test immediately.

public final class NetworkMockBuilder {

    // MARK: - Stub record

    public struct Stub {
        let method: String?          // nil = match any method
        let pathPrefix: String?      // nil = match any path
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        // MARK: Computed

        func matches(_ request: URLRequest) -> Bool {
            if let m = method, request.httpMethod?.uppercased() != m.uppercased() { return false }
            if let p = pathPrefix, !(request.url?.path.hasPrefix(p) ?? false) { return false }
            return true
        }

        func response(for request: URLRequest) -> (HTTPURLResponse, Data) {
            let url = request.url ?? URL(string: "https://test.invalid")!
            var allHeaders = headers
            if allHeaders["Content-Type"] == nil, !body.isEmpty {
                allHeaders["Content-Type"] = "application/json"
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: allHeaders
            )!
            return (response, body)
        }
    }

    // MARK: - State

    private var stubs: [Stub] = []
    private var fallbackBehavior: FallbackBehavior = .failTest

    public enum FallbackBehavior {
        case failTest            // XCTFail + URLError when no stub matched (default)
        case returnEmpty(Int)    // Return empty body with given status code
    }

    // MARK: - Init

    public init() {}

    // MARK: - Fluent builder methods

    @discardableResult
    public func stub(
        _ method: String? = nil,
        path: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        json: String
    ) -> Self {
        stub(method, path: path, statusCode: statusCode, headers: headers, body: Data(json.utf8))
    }

    @discardableResult
    public func stub(
        _ method: String? = nil,
        path: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        encodable: some Encodable
    ) -> Self {
        let data = (try? JSONEncoder().encode(encodable)) ?? Data()
        return stub(method, path: path, statusCode: statusCode, headers: headers, body: data)
    }

    @discardableResult
    public func stub(
        _ method: String? = nil,
        path: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> Self {
        stubs.append(Stub(
            method: method,
            pathPrefix: path,
            statusCode: statusCode,
            headers: headers,
            body: body
        ))
        return self
    }

    /// Convenience: respond with a BizarreCRM JSON envelope `{ success, data, message }`.
    @discardableResult
    public func stubEnvelope(
        _ method: String? = nil,
        path: String? = nil,
        statusCode: Int = 200,
        success: Bool = true,
        dataJSON: String? = nil,
        message: String? = nil
    ) -> Self {
        let dataField = dataJSON ?? "null"
        let msgField = message.map { "\"\($0)\"" } ?? "null"
        let json = #"{"success":\#(success),"data":\#(dataField),"message":\#(msgField)}"#
        return stub(method, path: path, statusCode: statusCode, json: json)
    }

    /// Configure fallback when no stub matches an incoming request.
    @discardableResult
    public func onUnmatchedRequest(_ behavior: FallbackBehavior) -> Self {
        fallbackBehavior = behavior
        return self
    }

    // MARK: - Build

    /// Install stubs into `MockURLProtocol` and return a configured `URLSession`.
    ///
    /// Each call replaces the previous handler — call `MockURLProtocol.reset()` in
    /// `tearDown()` to avoid inter-test pollution.
    public func buildSession(file: StaticString = #file, line: UInt = #line) -> URLSession {
        let capturedStubs = stubs
        let fallback = fallbackBehavior

        MockURLProtocol.requestHandler = { request in
            if let stub = capturedStubs.first(where: { $0.matches(request) }) {
                return stub.response(for: request)
            }
            // No stub matched.
            switch fallback {
            case .failTest:
                XCTFail(
                    "NetworkMockBuilder: no stub matched \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")",
                    file: file, line: line
                )
                throw URLError(.badServerResponse)
            case .returnEmpty(let code):
                let url = request.url ?? URL(string: "https://test.invalid")!
                let response = HTTPURLResponse(url: url, statusCode: code,
                                               httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, Data())
            }
        }

        return URLSession(configuration: MockURLProtocol.ephemeralConfiguration())
    }

    /// Return a snapshot of the registered stubs (for assertion in tests).
    public var registeredStubs: [Stub] { stubs }
}

// MARK: - NetworkMockBuilderTests

final class NetworkMockBuilderTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test_builder_matchesMethodAndPath() async throws {
        let session = NetworkMockBuilder()
            .stub("GET", path: "/api/v1/tickets", json: #"{"success":true,"data":[],"message":null}"#)
            .buildSession()

        let url = URL(string: "https://test.invalid/api/v1/tickets")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertFalse(data.isEmpty)
    }

    func test_builder_multipleStubs_secondMatchesPost() async throws {
        let session = NetworkMockBuilder()
            .stub("GET",  path: "/api/v1/tickets", json: #"{"success":true,"data":[],"message":null}"#)
            .stub("POST", path: "/api/v1/tickets", statusCode: 201,
                  json: #"{"success":true,"data":{"id":99},"message":null}"#)
            .buildSession()

        let url = URL(string: "https://test.invalid/api/v1/tickets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"title":"New"}"#.utf8)

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 201)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dataObj = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual(dataObj["id"] as? Int, 99)
    }

    func test_builder_envelopeConvenience() async throws {
        let session = NetworkMockBuilder()
            .stubEnvelope("GET", path: "/api/v1/customers", dataJSON: "[1,2,3]")
            .buildSession()

        let url = URL(string: "https://test.invalid/api/v1/customers")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await session.data(for: request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["success"] as? Bool, true)
    }

    func test_builder_registeredStubsCount() {
        let builder = NetworkMockBuilder()
            .stub("GET", path: "/a")
            .stub("POST", path: "/b", statusCode: 201)
        XCTAssertEqual(builder.registeredStubs.count, 2)
    }

    func test_builder_noMethodFilter_matchesAnyMethod() async throws {
        let session = NetworkMockBuilder()
            .stub(path: "/api/v1/ping", json: #"{"pong":true}"#)
            .buildSession()

        for method in ["GET", "POST", "PUT", "DELETE"] {
            var request = URLRequest(url: URL(string: "https://test.invalid/api/v1/ping")!)
            request.httpMethod = method
            let (_, response) = try await session.data(for: request)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200, "Expected 200 for \(method)")
        }
    }
}
