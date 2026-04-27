import XCTest
@testable import Auth
import Networking

// MARK: - §2.1 SetupStatusProbe tests

@MainActor
final class SetupStatusProbeTests: XCTestCase {

    // MARK: - needsSetup

    func test_probe_whenNeedsSetupTrue_returnsNeedsSetup() async {
        let stub = SetupProbeAPIStub(status: AuthSetupStatus(needsSetup: true, isMultiTenant: false))
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: false)

        let result = await probe.run()

        XCTAssertEqual(result, .needsSetup)
    }

    // MARK: - needsTenantPicker

    func test_probe_whenMultiTenantAndNoSavedTenant_returnsNeedsTenantPicker() async {
        let stub = SetupProbeAPIStub(status: AuthSetupStatus(needsSetup: false, isMultiTenant: true))
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: false)

        let result = await probe.run()

        XCTAssertEqual(result, .needsTenantPicker)
    }

    // MARK: - proceedToLogin

    func test_probe_whenMultiTenantAndHasSavedTenant_proceedsToLogin() async {
        let stub = SetupProbeAPIStub(status: AuthSetupStatus(needsSetup: false, isMultiTenant: true))
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: true)

        let result = await probe.run()

        XCTAssertEqual(result, .proceedToLogin)
    }

    func test_probe_whenNeedsSetupFalseAndSingleTenant_proceedsToLogin() async {
        let stub = SetupProbeAPIStub(status: AuthSetupStatus(needsSetup: false, isMultiTenant: false))
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: false)

        let result = await probe.run()

        XCTAssertEqual(result, .proceedToLogin)
    }

    // MARK: - failed

    func test_probe_whenNetworkError_returnsFailed() async {
        let stub = SetupProbeAPIStub(shouldThrow: true)
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: false)

        let result = await probe.run()

        if case .failed = result {
            // Correct
        } else {
            XCTFail("Expected .failed, got \(result)")
        }
    }

    // MARK: - needsSetup takes priority

    func test_probe_whenNeedsSetupAndMultiTenant_needsSetupTakesPriority() async {
        let stub = SetupProbeAPIStub(status: AuthSetupStatus(needsSetup: true, isMultiTenant: true))
        let probe = SetupStatusProbe(api: stub, hasSavedTenant: false)

        let result = await probe.run()

        XCTAssertEqual(result, .needsSetup)
    }
}

// MARK: - Stub APIClient for probe tests

private actor SetupProbeAPIStub: APIClient {
    private let status: AuthSetupStatus?
    private let shouldThrow: Bool

    init(status: AuthSetupStatus? = nil, shouldThrow: Bool = false) {
        self.status = status
        self.shouldThrow = shouldThrow
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldThrow { throw APITransportError.networkUnavailable }
        guard let s = status as? T else { throw APITransportError.invalidResponse }
        return s
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
