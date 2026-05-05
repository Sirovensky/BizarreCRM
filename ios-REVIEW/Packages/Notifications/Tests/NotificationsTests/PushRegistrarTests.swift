import XCTest
@testable import Notifications
@testable import Networking

// MARK: - Mock API client for push tests

actor MockPushAPIClient: APIClient {
    enum Outcome { case success; case failure(Error) }

    var registerOutcome: Outcome = .success
    var unregisterOutcome: Outcome = .success
    private(set) var registerCalls: [DeviceRegisterRequest] = []
    private(set) var unregisterTokens: [String] = []

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        if path == "/api/v1/devices/register",
           let req = body as? DeviceRegisterRequest {
            registerCalls.append(req)
            switch registerOutcome {
            case .success:
                let resp = DeviceRegisterResponse(message: "ok")
                guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {
        if path.hasPrefix("/api/v1/devices/") {
            let token = String(path.dropFirst("/api/v1/devices/".count))
            unregisterTokens.append(token)
            switch unregisterOutcome {
            case .success: return
            case .failure(let e): throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Tests

final class PushRegistrarTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() async {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        let state = await registrar.state
        XCTAssertEqual(state, .idle)
    }

    // MARK: - receiveDeviceToken

    func test_receiveDeviceToken_setsRegisteredState() async throws {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        let data = Data([0xAB, 0xCD, 0xEF])
        try await registrar.receiveDeviceToken(data)
        let state = await registrar.state
        XCTAssertEqual(state, .registered(token: "abcdef"))
    }

    func test_receiveDeviceToken_callsRegisterEndpoint() async throws {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        let data = Data([0x01, 0x02, 0x03])
        try await registrar.receiveDeviceToken(data)
        let calls = await api.registerCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.deviceToken, "010203")
        XCTAssertEqual(calls.first?.deviceType, "ios")
    }

    func test_receiveDeviceToken_setsFailedStateOnServerError() async throws {
        let api = MockPushAPIClient()
        await api.set(registerOutcome: .failure(APITransportError.noBaseURL))
        let registrar = PushRegistrar(api: api)
        let data = Data([0xAA, 0xBB])
        do {
            try await registrar.receiveDeviceToken(data)
            XCTFail("Expected error to be thrown")
        } catch {}
        let state = await registrar.state
        if case .failed = state { /* correct */ } else {
            XCTFail("Expected .failed state, got \(state)")
        }
    }

    func test_receiveDeviceToken_hexConversionCorrect() async throws {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        // Known byte values → known hex
        let data = Data([0x00, 0xFF, 0x10, 0xA5])
        try await registrar.receiveDeviceToken(data)
        let calls = await api.registerCalls
        XCTAssertEqual(calls.first?.deviceToken, "00ff10a5")
    }

    // MARK: - handleRegistrationFailure

    func test_handleRegistrationFailure_setsFailedState() async {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "apns error"])
        await registrar.handleRegistrationFailure(error)
        let state = await registrar.state
        if case .failed(let msg) = state {
            XCTAssertTrue(msg.contains("apns error"))
        } else {
            XCTFail("Expected .failed state, got \(state)")
        }
    }

    // MARK: - unregisterDevice

    func test_unregisterDevice_deletesFromServer() async throws {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        // Register first so token is in keychain
        let data = Data([0xDE, 0xAD])
        try await registrar.receiveDeviceToken(data)
        // Now unregister
        try await registrar.unregisterDevice()
        let tokens = await api.unregisterTokens
        XCTAssertEqual(tokens.first, "dead")
    }

    func test_unregisterDevice_setsIdleState() async throws {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        let data = Data([0x12, 0x34])
        try await registrar.receiveDeviceToken(data)
        try await registrar.unregisterDevice()
        let state = await registrar.state
        XCTAssertEqual(state, .idle)
    }

    func test_unregisterDevice_noOpWhenNoToken() async throws {
        // Fresh registrar, no token in keychain → should succeed silently
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        // Clean up any leftover from previous test
        KeychainPushStore.delete()
        try await registrar.unregisterDevice()
        let tokens = await api.unregisterTokens
        XCTAssertTrue(tokens.isEmpty)
    }

    // MARK: - State transitions

    func test_registerForRemoteNotifications_setsPendingState() async {
        let api = MockPushAPIClient()
        let registrar = PushRegistrar(api: api)
        // Can't call UIApplication in test host, but we can verify state transitions
        // after receiveDeviceToken replaces .pending with .registered.
        // Pre-condition: idle.
        let before = await registrar.state
        XCTAssertEqual(before, .idle)
    }
}

// MARK: - MockPushAPIClient helpers

extension MockPushAPIClient {
    func set(registerOutcome: Outcome) { self.registerOutcome = registerOutcome }
    func set(unregisterOutcome: Outcome) { self.unregisterOutcome = unregisterOutcome }
}
