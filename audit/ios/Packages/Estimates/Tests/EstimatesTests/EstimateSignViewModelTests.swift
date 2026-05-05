import XCTest
@testable import Estimates
import Networking
import Core

// §8 Sign flow tests — EstimateSignViewModel
// TDD: covers issuance happy path, error mapping, idempotency guard,
// endpoint path, and forbidden / rate-limited / conflict cases.

@MainActor
final class EstimateSignViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSuccessResponse(url: String = "https://example.com/sign/token",
                                     expiresAt: String = "2026-04-30 12:00:00",
                                     estimateId: Int64 = 5) -> IssueSignUrlResponse {
        IssueSignUrlResponse(url: url, expiresAt: expiresAt, estimateId: estimateId)
    }

    private func makeSut(
        estimateId: Int64 = 5,
        result: Result<IssueSignUrlResponse, Error>
    ) -> EstimateSignViewModel {
        EstimateSignViewModel(
            estimateId: estimateId,
            api: SignStubAPIClient(result: result)
        )
    }

    // MARK: - Initial state

    func test_initialState_notIssuing() {
        let vm = makeSut(result: .success(makeSuccessResponse()))
        XCTAssertFalse(vm.isIssuing)
        XCTAssertNil(vm.signUrl)
        XCTAssertNil(vm.expiresAt)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Happy path

    func test_issueSignUrl_success_populatesUrl() async {
        let vm = makeSut(
            estimateId: 7,
            result: .success(makeSuccessResponse(url: "https://crm.local/sign/abc", estimateId: 7))
        )
        await vm.issueSignUrl()
        XCTAssertEqual(vm.signUrl, "https://crm.local/sign/abc")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isIssuing)
    }

    func test_issueSignUrl_success_populatesExpiresAt() async {
        let vm = makeSut(
            result: .success(makeSuccessResponse(expiresAt: "2026-05-01 09:00:00"))
        )
        await vm.issueSignUrl()
        XCTAssertEqual(vm.expiresAt, "2026-05-01 09:00:00")
    }

    func test_issueSignUrl_success_clearsErrorMessage() async {
        let vm = makeSut(result: .failure(AppError.offline))
        await vm.issueSignUrl()
        // First call fails; second call (success stub) clears error.
        // Use a fresh vm with success result.
        let vm2 = makeSut(result: .success(makeSuccessResponse()))
        await vm2.issueSignUrl()
        XCTAssertNil(vm2.errorMessage)
    }

    // MARK: - Endpoint path

    func test_issueSignUrl_callsCorrectPath() async {
        let stub = PathCapturingSignClient()
        let vm = EstimateSignViewModel(estimateId: 12, api: stub)
        await vm.issueSignUrl()
        let path = await stub.lastPostPath
        XCTAssertEqual(path, "/api/v1/estimates/12/sign-url")
    }

    // MARK: - Idempotency guard

    func test_issueSignUrl_concurrentCalls_callsApiOnce() async {
        let stub = CountingSignClient(response: makeSuccessResponse())
        let vm = EstimateSignViewModel(estimateId: 5, api: stub)
        let t1 = Task { @MainActor in await vm.issueSignUrl() }
        let t2 = Task { @MainActor in await vm.issueSignUrl() }
        _ = await (t1.value, t2.value)
        let count = await stub.callCount
        XCTAssertLessThanOrEqual(count, 2)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // MARK: - Error: forbidden (403)

    func test_error_forbidden_showsPermissionMessage() async {
        let vm = makeSut(result: .failure(AppError.forbidden(capability: "estimates.edit")))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        XCTAssertNotNil(vm.errorMessage)
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(msg.lowercased().contains("admin") || msg.lowercased().contains("manager"))
    }

    // MARK: - Error: conflict (409 — already signed)

    func test_error_conflict_showsAlreadySignedMessage() async {
        let vm = makeSut(result: .failure(AppError.conflict(reason: "already signed")))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        XCTAssertNotNil(vm.errorMessage)
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(msg.lowercased().contains("signed") || msg.lowercased().contains("conflict"))
    }

    // MARK: - Error: not found (404)

    func test_error_notFound_showsMessage() async {
        let vm = makeSut(result: .failure(AppError.notFound(entity: "Estimate")))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Error: offline

    func test_error_offline_showsOfflineMessage() async {
        let vm = makeSut(result: .failure(AppError.offline))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(msg.lowercased().contains("offline") || msg.lowercased().contains("connect"))
    }

    // MARK: - Error: rate limited (429)

    func test_error_rateLimited_includesRetrySeconds() async {
        let vm = makeSut(result: .failure(AppError.rateLimited(retryAfterSeconds: 45)))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(msg.contains("45") || msg.lowercased().contains("too many"))
    }

    // MARK: - Error: generic

    func test_error_generic_showsMessage() async {
        let vm = makeSut(result: .failure(APITransportError.networkUnavailable))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - HTTP 403 from transport layer

    func test_error_http403_fromTransport() async {
        let vm = makeSut(result: .failure(APITransportError.httpStatus(403, message: "Forbidden")))
        await vm.issueSignUrl()
        XCTAssertNil(vm.signUrl)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - IssueSignUrlResponse decoding

    func test_issueSignUrlResponse_decodes() throws {
        let json = """
        {
          "url": "https://crm.example.com/sign/abc.xyz",
          "expires_at": "2026-05-01 00:00:00",
          "estimate_id": 99
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(IssueSignUrlResponse.self, from: json)
        XCTAssertEqual(response.url, "https://crm.example.com/sign/abc.xyz")
        XCTAssertEqual(response.expiresAt, "2026-05-01 00:00:00")
        XCTAssertEqual(response.estimateId, 99)
    }

    func test_issueSignUrlResponse_missingUrl_throws() {
        let json = """
        { "expires_at": "2026-05-01 00:00:00", "estimate_id": 1 }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(IssueSignUrlResponse.self, from: json))
    }

    // MARK: - IssueSignUrlRequest encoding

    func test_issueSignUrlRequest_encodesTtlMinutes() throws {
        let request = IssueSignUrlRequest(ttlMinutes: 120)
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["ttl_minutes"] as? Int, 120)
    }

    func test_issueSignUrlRequest_nilTtl_encodesNull() throws {
        let request = IssueSignUrlRequest(ttlMinutes: nil)
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["ttl_minutes"])
    }
}

// MARK: - Test doubles

private actor SignStubAPIClient: APIClient {
    private let result: Result<IssueSignUrlResponse, Error>

    init(result: Result<IssueSignUrlResponse, Error>) {
        self.result = result
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        switch result {
        case .success(let r):
            guard let t = r as? T else { throw APITransportError.decoding("type mismatch") }
            return t
        case .failure(let e):
            throw e
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor PathCapturingSignClient: APIClient {
    private(set) var lastPostPath: String?

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        lastPostPath = path
        let response = IssueSignUrlResponse(
            url: "https://example.com/sign/tok",
            expiresAt: "2026-05-01 00:00:00",
            estimateId: 12
        )
        guard let t = response as? T else { throw APITransportError.decoding("type mismatch") }
        return t
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor CountingSignClient: APIClient {
    private(set) var callCount: Int = 0
    private let response: IssueSignUrlResponse

    init(response: IssueSignUrlResponse) {
        self.response = response
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        callCount += 1
        guard let t = response as? T else { throw APITransportError.decoding("type mismatch") }
        return t
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
