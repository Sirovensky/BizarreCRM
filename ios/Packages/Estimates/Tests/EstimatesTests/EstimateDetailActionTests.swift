import XCTest
@testable import Estimates
import Networking
import Core

// MARK: - EstimateDetailActionTests (§8.2)
//
// Covers: send, approve, reject, convert-to-invoice, versions,
//         EstimateStatusFilter enum, APIClient request types.

final class EstimateDetailActionTests: XCTestCase {

    // MARK: - EstimateSendRequest encoding

    func testSendRequestEncoding_smsOnly() throws {
        let req = EstimateSendRequest(sendSms: true, sendEmail: nil)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["send_sms"] as? Bool, true)
        XCTAssertNil(dict?["send_email"])
    }

    func testSendRequestEncoding_emailOnly() throws {
        let req = EstimateSendRequest(sendSms: nil, sendEmail: true)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["send_email"] as? Bool, true)
    }

    func testSendRequestEncoding_bothChannels() throws {
        let req = EstimateSendRequest(sendSms: true, sendEmail: true)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["send_sms"] as? Bool, true)
        XCTAssertEqual(dict?["send_email"] as? Bool, true)
    }

    // MARK: - EstimateApproveRequest encoding

    func testApproveRequest_staffApprovedTrueAndNoToken() throws {
        let req = EstimateApproveRequest(token: nil, staffApproved: true, signatureData: nil)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["staff_approved"] as? Bool, true)
        XCTAssertNil(dict?["token"])
    }

    func testApproveRequest_withSignatureData() throws {
        let req = EstimateApproveRequest(token: nil, staffApproved: true, signatureData: "abc123")
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["signature_data"] as? String, "abc123")
    }

    // MARK: - EstimateRejectRequest encoding

    func testRejectRequest_hasStatusRejected() throws {
        let req = EstimateRejectRequest(reason: "Price too high")
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["status"] as? String, "rejected")
        XCTAssertEqual(dict?["rejection_reason"] as? String, "Price too high")
    }

    // MARK: - EstimateBulkRequest encoding

    func testBulkRequestEncoding_sendAction() throws {
        let req = EstimateBulkRequest(ids: [1, 2, 3], action: .send)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["action"] as? String, "send")
        let ids = dict?["estimate_ids"] as? [Int]
        XCTAssertEqual(ids?.count, 3)
    }

    func testBulkRequestEncoding_deleteAction() throws {
        let req = EstimateBulkRequest(ids: [5], action: .delete)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["action"] as? String, "delete")
    }

    func testBulkRequestEncoding_exportAction() throws {
        let req = EstimateBulkRequest(ids: [], action: .export)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["action"] as? String, "export")
    }

    // MARK: - EstimateVersion decoding

    func testEstimateVersionDecoding() throws {
        let json = """
        {"id":1,"estimate_id":42,"version_number":3,"created_at":"2026-04-01","total":250.0,"status":"draft"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let version = try decoder.decode(EstimateVersion.self, from: json)
        XCTAssertEqual(version.id, 1)
        XCTAssertEqual(version.estimateId, 42)
        XCTAssertEqual(version.versionNumber, 3)
        XCTAssertEqual(version.total, 250.0)
        XCTAssertEqual(version.status, "draft")
    }

    func testEstimateVersionsResponseDecoding() throws {
        let json = """
        {"versions":[{"id":1,"estimate_id":10,"version_number":1,"total":100.0}]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(EstimateVersionsResponse.self, from: json)
        XCTAssertEqual(response.versions.count, 1)
        XCTAssertEqual(response.versions[0].versionNumber, 1)
    }

    // MARK: - IssueSignUrlRequest encoding

    func testIssueSignUrlRequest_withTtl() throws {
        let req = IssueSignUrlRequest(ttlMinutes: 1440)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["ttl_minutes"] as? Int, 1440)
    }

    func testIssueSignUrlRequest_withoutTtl() throws {
        let req = IssueSignUrlRequest(ttlMinutes: nil)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["ttl_minutes"])
    }

    // MARK: - EstimateSendViewModel behavior

    @MainActor
    func testSendViewModel_cannotSendWithBothFalse() async {
        let vm = EstimateSendViewModel(api: SpySendAPIClient(), estimateId: 1)
        vm.sendSms = false
        vm.sendEmail = false
        await vm.send()
        // Neither channel → no request sent, didSend remains false
        XCTAssertFalse(vm.didSend)
    }

    @MainActor
    func testSendViewModel_happyPath_didSend() async {
        let vm = EstimateSendViewModel(api: SpySendAPIClient(shouldSucceed: true), estimateId: 1)
        vm.sendSms = true
        await vm.send()
        XCTAssertTrue(vm.didSend)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testSendViewModel_failure_setsError() async {
        let vm = EstimateSendViewModel(api: SpySendAPIClient(shouldSucceed: false), estimateId: 1)
        vm.sendEmail = true
        await vm.send()
        XCTAssertFalse(vm.didSend)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - EstimateRejectViewModel behavior

    @MainActor
    func testRejectViewModel_cannotRejectWithEmptyReason() {
        let vm = EstimateRejectViewModel(api: SpyRejectAPIClient(), estimateId: 1)
        vm.reason = ""
        XCTAssertFalse(vm.canReject)
    }

    @MainActor
    func testRejectViewModel_canRejectWithReason() {
        let vm = EstimateRejectViewModel(api: SpyRejectAPIClient(), estimateId: 1)
        vm.reason = "Too expensive"
        XCTAssertTrue(vm.canReject)
    }

    @MainActor
    func testRejectViewModel_happyPath_didReject() async {
        let vm = EstimateRejectViewModel(api: SpyRejectAPIClient(shouldSucceed: true), estimateId: 1)
        vm.reason = "Budget cut"
        await vm.reject()
        XCTAssertTrue(vm.didReject)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testRejectViewModel_failure_setsError() async {
        let vm = EstimateRejectViewModel(api: SpyRejectAPIClient(shouldSucceed: false), estimateId: 1)
        vm.reason = "Budget cut"
        await vm.reject()
        XCTAssertFalse(vm.didReject)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - EstimateVersionsViewModel behavior

    @MainActor
    func testVersionsViewModel_loadsVersions() async {
        let vm = EstimateVersionsViewModel(
            api: SpyVersionsAPIClient(versions: [makeVersion(id: 1, vn: 1), makeVersion(id: 2, vn: 2)]),
            estimateId: 42,
            currentVersionNumber: 2
        )
        await vm.load()
        XCTAssertEqual(vm.versions.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testVersionsViewModel_currentVersionNumber() async {
        let vm = EstimateVersionsViewModel(
            api: SpyVersionsAPIClient(versions: []),
            estimateId: 42,
            currentVersionNumber: 3
        )
        XCTAssertEqual(vm.currentVersionNumber, 3)
    }

    @MainActor
    func testVersionsViewModel_failureSetError() async {
        let vm = EstimateVersionsViewModel(
            api: SpyVersionsAPIClient(shouldFail: true),
            estimateId: 42,
            currentVersionNumber: nil
        )
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.versions.isEmpty)
    }
}

// MARK: - Helpers

private func makeVersion(id: Int64, vn: Int) -> EstimateVersion {
    let json = """
    {"id":\(id),"estimate_id":42,"version_number":\(vn),"total":100.0}
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(EstimateVersion.self, from: json)
}

// MARK: - Spy API clients

private actor SpySendAPIClient: APIClient {
    let shouldSucceed: Bool
    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if !shouldSucceed { throw APITransportError.networkFailure(URLError(.notConnectedToInternet)) }
        if path.hasSuffix("/send") {
            let r = EstimateSendResponse(estimateId: 1, approvalLink: "https://example.com/approve/abc")
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
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

private actor SpyRejectAPIClient: APIClient {
    let shouldSucceed: Bool
    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if !shouldSucceed { throw APITransportError.networkFailure(URLError(.notConnectedToInternet)) }
        // Return a minimal Estimate
        let json = """
        {"id":1,"order_id":"EST-1","customer_first_name":"Test","customer_last_name":"User","status":"rejected","total":100.0}
        """.data(using: .utf8)!
        let est = try JSONDecoder().decode(Estimate.self, from: json)
        guard let cast = est as? T else { throw APITransportError.decoding("type") }
        return cast
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor SpyVersionsAPIClient: APIClient {
    let versions: [EstimateVersion]
    let shouldFail: Bool

    init(versions: [EstimateVersion] = [], shouldFail: Bool = false) {
        self.versions = versions
        self.shouldFail = shouldFail
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw APITransportError.networkFailure(URLError(.notConnectedToInternet)) }
        if path.contains("/versions") && !path.contains("/versions/") {
            let r = EstimateVersionsResponse(versions: versions)
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
