import XCTest
@testable import Auth
import Networking

// MARK: - §2.8 BackupCodeRecoveryViewModel tests

@MainActor
final class BackupCodeRecoveryViewModelTests: XCTestCase {

    // MARK: - canSubmit validation

    func test_canSubmit_falseWhenAllEmpty() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        XCTAssertFalse(vm.canSubmit)
    }

    func test_canSubmit_falseWhenBackupCodeTooShort() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        vm.username = "alice"
        vm.password = "password123"
        vm.backupCode = "SHORT"
        XCTAssertFalse(vm.canSubmit, "Code < 8 chars should not allow submit")
    }

    func test_canSubmit_falseWhenUsernameEmpty() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        vm.username = ""
        vm.password = "password123"
        vm.backupCode = "ABCD1234EFGH"
        XCTAssertFalse(vm.canSubmit, "Empty username should not allow submit")
    }

    func test_canSubmit_falseWhenPasswordEmpty() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        vm.username = "alice"
        vm.password = ""
        vm.backupCode = "ABCD1234EFGH"
        XCTAssertFalse(vm.canSubmit)
    }

    func test_canSubmit_trueWithValidInputs() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        vm.username = "alice"
        vm.password = "password123"
        vm.backupCode = "ABCD1234EFGH"
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_falseWhileSubmitting() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub())
        vm.username = "alice"
        vm.password = "password123"
        vm.backupCode = "ABCD1234EFGH"
        vm.isSubmitting = true
        XCTAssertFalse(vm.canSubmit, "Should not allow submit while already submitting")
    }

    func test_usernameHintPrefilled() {
        let vm = BackupCodeRecoveryViewModel(api: MockRecoveryAPIStub(), usernameHint: "bob")
        XCTAssertEqual(vm.username, "bob")
    }

    // MARK: - Submit success

    func test_submit_success_setsRecoveryToken() async {
        let stub = MockRecoveryAPIStub(result: .success("tok123"))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "pass"
        vm.backupCode = "ABCD1234EFGH"

        await vm.submit()

        XCTAssertEqual(vm.recoveryToken, "tok123")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }

    // MARK: - Submit errors

    func test_submit_invalidCode_setsErrorMessage() async {
        let stub = MockRecoveryAPIStub(result: .failure(APITransportError.httpStatus(400, "bad code")))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "pass"
        vm.backupCode = "BADCODE12"

        await vm.submit()

        XCTAssertNil(vm.recoveryToken)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("Invalid backup code") == true)
    }

    func test_submit_wrongCredentials_setsErrorMessage() async {
        let stub = MockRecoveryAPIStub(result: .failure(APITransportError.httpStatus(401, nil)))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "wrongpass"
        vm.backupCode = "ABCD1234EFGH"

        await vm.submit()

        XCTAssertNil(vm.recoveryToken)
        XCTAssertTrue(vm.errorMessage?.contains("incorrect") == true)
    }

    func test_submit_alreadyUsedCode_setsErrorMessage() async {
        let stub = MockRecoveryAPIStub(result: .failure(APITransportError.httpStatus(410, nil)))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "pass"
        vm.backupCode = "ABCD1234EFGH"

        await vm.submit()

        XCTAssertTrue(vm.errorMessage?.contains("already been used") == true)
    }

    func test_submit_networkError_setsErrorMessage() async {
        let stub = MockRecoveryAPIStub(result: .failure(APITransportError.noBaseURL))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "pass"
        vm.backupCode = "ABCD1234EFGH"

        await vm.submit()

        XCTAssertNil(vm.recoveryToken)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Code normalisation (dashes stripped, uppercased)

    func test_submit_normalisesBackupCode() async {
        let stub = MockRecoveryAPIStub(result: .success("tok999"))
        let vm = BackupCodeRecoveryViewModel(api: stub)
        vm.username = "alice"
        vm.password = "pass"
        // Entered with dash and lowercase — should normalise before sending
        vm.backupCode = "abcd-1234efgh"

        await vm.submit()

        XCTAssertEqual(stub.capturedBackupCode, "ABCD1234EFGH")
    }
}

// MARK: - Mock

private final class MockRecoveryAPIStub: APIClient, @unchecked Sendable {

    enum StubResult {
        case success(String)
        case failure(Error)
    }

    private let result: StubResult
    private(set) var capturedBackupCode: String?

    init(result: StubResult = .success("tok")) {
        self.result = result
    }

    var baseURL: URL? { nil }
    func setBaseURL(_ url: URL?) async {}

    func get<T: Decodable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Intercept the backup-code recovery call
        if path.contains("recover-with-backup-code") {
            // Decode body to capture normalised code
            if let data = try? JSONEncoder().encode(body),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                capturedBackupCode = dict["backupCode"]
            }
            switch result {
            case .success(let token):
                let response = BackupCodeRecoveryResponse(recoveryToken: token)
                guard let r = response as? T else { throw APITransportError.decodingFailed }
                return r
            case .failure(let error):
                throw error
            }
        }
        throw APITransportError.noBaseURL
    }

    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIEnvelope<T> {
        throw APITransportError.noBaseURL
    }
}
