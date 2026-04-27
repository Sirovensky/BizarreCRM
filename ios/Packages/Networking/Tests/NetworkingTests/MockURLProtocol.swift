import Foundation
import XCTest

// MARK: - §31.1 MockURLProtocol — HTTP stub for unit tests
//
// Intercepts URLSession requests and returns synthetic responses without hitting the network.
//
// Usage in tests:
//
//   // 1. Register the mock protocol before creating the session
//   MockURLProtocol.requestHandler = { request in
//       let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
//       return (response, Data(#"{"success":true,"data":null,"message":null}"#.utf8))
//   }
//
//   // 2. Create a URLSession configured to use MockURLProtocol
//   let config = URLSessionConfiguration.ephemeral
//   config.protocolClasses = [MockURLProtocol.self]
//   let session = URLSession(configuration: config)
//
//   // 3. Make requests through the session — they hit the handler, not the network.
//
// Thread-safety note:
//   `requestHandler` is intentionally a static var (not a class var) so tests can
//   set it from setUp() without subclassing. Tests must run serially or reset the
//   handler between parallel runs.

public final class MockURLProtocol: URLProtocol {

    // MARK: - Handler

    /// Set this before running a test to define how the mock should respond.
    ///
    /// Throws from the handler → propagates as URLError to the session task.
    public static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // MARK: - Request recording

    /// All requests intercepted since the last `reset()` call.
    public private(set) static var recordedRequests: [URLRequest] = []

    // MARK: - URLProtocol

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            let error = URLError(.badServerResponse,
                                 userInfo: [NSLocalizedDescriptionKey: "MockURLProtocol.requestHandler not set"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        MockURLProtocol.recordedRequests.append(request)

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}

    // MARK: - Helpers

    /// Reset the handler and request log between tests.
    public static func reset() {
        requestHandler = nil
        recordedRequests.removeAll()
    }

    /// Build a `URLSessionConfiguration` pre-wired to use this protocol.
    public static func ephemeralConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    /// Convenience: respond with a JSON envelope `{ success, data, message }`.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code (default 200).
    ///   - success: Value for the `success` field (default true).
    ///   - data: Optional JSON-encodable payload. Encoded as `data` in the envelope.
    ///   - message: Optional message string.
    public static func respondWithEnvelope(
        statusCode: Int = 200,
        success: Bool = true,
        dataJSON: String? = nil,
        message: String? = nil
    ) {
        requestHandler = { request in
            let url = request.url ?? URL(string: "https://test.invalid")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            let dataField: String
            if let d = dataJSON { dataField = d } else { dataField = "null" }
            let msgField: String
            if let m = message { msgField = "\"\(m)\"" } else { msgField = "null" }

            let body = """
            {"success":\(success),"data":\(dataField),"message":\(msgField)}
            """
            return (response, Data(body.utf8))
        }
    }
}
