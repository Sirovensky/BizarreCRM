import XCTest
import Combine
@testable import Networking

// MARK: - MultipartUploadServiceTests
//
// Integration tests for MultipartUploadService using URLProtocol stubs.
// A URLProtocol subclass intercepts requests made through a custom session
// and returns canned responses without hitting the network.

final class MultipartUploadServiceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Successful upload

    func testSuccessfulUploadReturns200AndResponseData() async throws {
        let responseBody = Data("""
        {"success":true,"message":"uploaded"}
        """.utf8)

        StubURLProtocol.stub(statusCode: 200, data: responseBody)

        let service = makeService()
        var form = MultipartFormData(boundary: "TEST")
        form.appendField(name: "title", value: "hello")
        let (body, _) = form.encode()

        var request = URLRequest(url: URL(string: "https://test.local/upload")!)
        request.httpMethod = "POST"
        request.applyMultipartForm(form)

        let (result, _) = try await service.upload(request: request, formData: body)

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.data, responseBody)
    }

    func testUploadThrowsHTTPErrorOnNon2xx() async {
        StubURLProtocol.stub(statusCode: 422, data: Data())

        let service = makeService()
        var form = MultipartFormData(boundary: "T")
        form.appendField(name: "x", value: "y")
        let (body, _) = form.encode()

        var request = URLRequest(url: URL(string: "https://test.local/upload")!)
        request.httpMethod = "POST"
        request.applyMultipartForm(form)

        do {
            _ = try await service.upload(request: request, formData: body)
            XCTFail("Expected error to be thrown")
        } catch MultipartUploadError.httpError(let code) {
            XCTAssertEqual(code, 422)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUploadThrowsHTTPErrorOn500() async {
        StubURLProtocol.stub(statusCode: 500, data: Data())

        let service = makeService()
        let form = MultipartFormData(boundary: "T")
        let (body, _) = form.encode()

        var request = URLRequest(url: URL(string: "https://test.local/upload")!)
        request.httpMethod = "POST"
        request.applyMultipartForm(form)

        do {
            _ = try await service.upload(request: request, formData: body)
            XCTFail("Expected error for 500")
        } catch MultipartUploadError.httpError(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Request body forwarded correctly

    func testUploadSendsMultipartContentTypeHeader() async throws {
        StubURLProtocol.stub(statusCode: 200, data: Data())

        let service = makeService()
        var form = MultipartFormData(boundary: "BOUNDARY123")
        form.appendField(name: "k", value: "v")
        let (body, _) = form.encode()

        var request = URLRequest(url: URL(string: "https://test.local/upload")!)
        request.httpMethod = "POST"
        request.applyMultipartForm(form)

        _ = try await service.upload(request: request, formData: body)

        let interceptedRequest = try XCTUnwrap(StubURLProtocol.lastRequest)
        let ct = interceptedRequest.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.contains("multipart/form-data"), "Content-Type must be multipart/form-data")
        XCTAssertTrue(ct.contains("BOUNDARY123"), "boundary must appear in Content-Type")
    }

    // MARK: - 201 Created is success

    func testUpload201IsSuccess() async throws {
        StubURLProtocol.stub(statusCode: 201, data: Data("{\"id\":1}".utf8))

        let service = makeService()
        let form = MultipartFormData(boundary: "B")
        let (body, _) = form.encode()

        var request = URLRequest(url: URL(string: "https://test.local/upload")!)
        request.httpMethod = "POST"
        request.applyMultipartForm(form)

        let (result, _) = try await service.upload(request: request, formData: body)
        XCTAssertEqual(result.statusCode, 201)
    }

    // MARK: - Factory helper

    private func makeService() -> MultipartUploadService {
        // Build a service wired to a URLSession backed by StubURLProtocol
        // rather than the real background session (which requires app entitlements
        // and a running run loop). We achieve this by creating a plain ephemeral
        // session with the stub registered, then using MultipartUploadServiceStub
        // to replace the session.
        return MultipartUploadService.makeWithStubSession()
    }
}

// MARK: - MultipartUploadService test seam

extension MultipartUploadService {
    /// Creates a service that uses an ephemeral URLSession backed by
    /// StubURLProtocol — suitable for unit tests only.
    static func makeWithStubSession() -> MultipartUploadService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Origin": "ios"]
        return MultipartUploadService(
            sessionIdentifier: "com.bizarrecrm.test.\(UUID().uuidString)",
            configuration: config
        )
    }
}

// MARK: - StubURLProtocol

/// A URLProtocol subclass that returns a canned HTTP response without
/// hitting the network. Register it via a URLSessionConfiguration.
final class StubURLProtocol: URLProtocol {

    // MARK: Shared stub configuration

    private static var stubbedStatusCode: Int = 200
    private static var stubbedData: Data = Data()
    private static var stubbedError: Error? = nil
    private(set) static var lastRequest: URLRequest? = nil

    static func stub(statusCode: Int, data: Data, error: Error? = nil) {
        stubbedStatusCode = statusCode
        stubbedData = data
        stubbedError = error
    }

    static func reset() {
        stubbedStatusCode = 200
        stubbedData = Data()
        stubbedError = nil
        lastRequest = nil
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request

        if let error = StubURLProtocol.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StubURLProtocol.stubbedStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.stubbedData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
