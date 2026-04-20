import XCTest
@testable import Auth
import Networking

/// §2.4 — State-machine tests for the 2FA verify step. Server I/O is stubbed;
/// we exercise the LoginFlow transitions around the backup-code toggle so a
/// silent regression (e.g. forgetting to clear `totpCode` on toggle) gets
/// caught before it lands in production.
@MainActor
final class TwoFactorFlowTests: XCTestCase {

    func test_defaultVerifyMode_isTOTP() {
        let flow = LoginFlow(api: StubAPIClient())
        XCTAssertFalse(flow.useBackupCode)
        XCTAssertEqual(flow.totpCode, "")
        XCTAssertEqual(flow.backupCodeInput, "")
    }

    func test_toggleBackupCode_clearsBothInputs() {
        let flow = LoginFlow(api: StubAPIClient())
        flow.totpCode = "123456"
        flow.backupCodeInput = "ABCD1234"
        flow.errorMessage = "prior"

        flow.toggleBackupCode()

        XCTAssertTrue(flow.useBackupCode)
        XCTAssertEqual(flow.totpCode, "")
        XCTAssertEqual(flow.backupCodeInput, "")
        XCTAssertNil(flow.errorMessage)
    }

    func test_toggleBackupCode_twiceReturnsToTOTPMode() {
        let flow = LoginFlow(api: StubAPIClient())
        flow.toggleBackupCode()
        flow.toggleBackupCode()
        XCTAssertFalse(flow.useBackupCode)
    }

    func test_backupCodesAndRemaining_initiallyAbsent() {
        let flow = LoginFlow(api: StubAPIClient())
        XCTAssertTrue(flow.backupCodes.isEmpty)
        XCTAssertNil(flow.remainingBackupCodes)
    }

    /// Submitting from a non-verify step is a no-op — protects against the
    /// UI wiring accidentally firing the request while on the SERVER panel.
    func test_submitTwoFactorVerify_noopsWhenNotOnVerifyStep() async {
        let flow = LoginFlow(api: StubAPIClient())
        XCTAssertEqual(flow.step, .server)
        await flow.submitTwoFactorVerify()
        XCTAssertEqual(flow.step, .server)
        XCTAssertFalse(flow.isSubmitting)
        // No error should fire — we simply ignored the call.
        XCTAssertNil(flow.errorMessage)
    }
}

private actor StubAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
