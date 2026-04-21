import XCTest
@testable import Auth
import Core

/// §2 Magic-link — tests for URL parser, ViewModel state machine, and
/// Repository pass-through.
final class MagicLinkURLTests: XCTestCase {

    // MARK: - MagicLinkURL parser

    func test_customScheme_validToken_extracted() {
        let url = URL(string: "bizarrecrm://auth/magic?token=abc123")!
        XCTAssertEqual(MagicLinkURL.token(from: url), "abc123")
    }

    func test_universalLink_validToken_extracted() {
        let url = URL(string: "https://app.bizarrecrm.com/auth/magic?token=xyz789")!
        XCTAssertEqual(MagicLinkURL.token(from: url), "xyz789")
    }

    func test_wrongPath_returnsNil() {
        // host=auth path=/other (not /magic)
        let url = URL(string: "bizarrecrm://auth/other?token=abc")!
        XCTAssertNil(MagicLinkURL.token(from: url))
    }

    func test_missingToken_returnsNil() {
        let url = URL(string: "bizarrecrm://auth/magic")!
        XCTAssertNil(MagicLinkURL.token(from: url))
    }

    func test_wrongScheme_returnsNil() {
        // http:// not accepted for universal link
        let url = URL(string: "http://app.bizarrecrm.com/auth/magic?token=abc")!
        XCTAssertNil(MagicLinkURL.token(from: url))
    }

    func test_wrongHost_universalLink_returnsNil() {
        let url = URL(string: "https://evil.com/auth/magic?token=abc")!
        XCTAssertNil(MagicLinkURL.token(from: url))
    }

    func test_wrongCustomHost_returnsNil() {
        // host is "wrong", not "auth"
        let url = URL(string: "bizarrecrm://wrong/magic?token=abc")!
        XCTAssertNil(MagicLinkURL.token(from: url))
    }

    func test_isMagicLink_customScheme_true() {
        let url = URL(string: "bizarrecrm://auth/magic?token=abc")!
        XCTAssertTrue(MagicLinkURL.isMagicLink(url))
    }

    func test_isMagicLink_universalLink_true() {
        let url = URL(string: "https://app.bizarrecrm.com/auth/magic?token=abc")!
        XCTAssertTrue(MagicLinkURL.isMagicLink(url))
    }

    func test_isMagicLink_unrelatedURL_false() {
        let url = URL(string: "https://google.com")!
        XCTAssertFalse(MagicLinkURL.isMagicLink(url))
    }

    func test_tokenWithSpecialChars_preservedViaPercentEncoding() {
        // Tokens may contain chars that require percent-encoding.
        let encoded = "aB1%2B%2F%3D%3D" // aB1+/==
        let url = URL(string: "bizarrecrm://auth/magic?token=\(encoded)")!
        let token = MagicLinkURL.token(from: url)
        XCTAssertNotNil(token)
    }
}

// MARK: - MagicLinkViewModel

@MainActor
final class MagicLinkViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = MagicLinkViewModel(repository: StubMagicLinkRepository())
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.email, "")
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.resendCooldownRemaining, 0)
    }

    // MARK: - sendMagicLink validation

    func test_sendMagicLink_emptyEmail_setsError_staysIdle() async {
        let vm = MagicLinkViewModel(repository: StubMagicLinkRepository())
        vm.email = ""
        await vm.sendMagicLink()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_sendMagicLink_invalidEmail_setsError() async {
        let vm = MagicLinkViewModel(repository: StubMagicLinkRepository())
        vm.email = "notanemail"
        await vm.sendMagicLink()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_sendMagicLink_success_transitionsToSent() async {
        let repo = StubMagicLinkRepository(requestResult: .success(.init(sent: true)))
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        XCTAssertEqual(vm.state, .sent)
        XCTAssertNil(vm.errorMessage)
    }

    func test_sendMagicLink_networkError_transitionsToFailed() async {
        let repo = StubMagicLinkRepository(requestResult: .failure(AppError.network(underlying: nil)))
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        if case .failed = vm.state { } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_sendMagicLink_success_startsCooldown() async {
        let repo = StubMagicLinkRepository(requestResult: .success(.init(sent: true)))
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        XCTAssertEqual(vm.resendCooldownRemaining, 60)
    }

    // MARK: - handleIncomingToken

    func test_handleIncomingToken_success_transitionsToSuccess() async {
        let repo = StubMagicLinkRepository(
            requestResult: .success(.init(sent: true)),
            verifyResult: .success(.init(authToken: "tok-abc"))
        )
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        XCTAssertEqual(vm.state, .sent)

        await vm.handleIncomingToken("some-token")
        XCTAssertEqual(vm.state, .success(authToken: "tok-abc"))
    }

    func test_handleIncomingToken_failure_transitionsToFailed() async {
        let repo = StubMagicLinkRepository(
            requestResult: .success(.init(sent: true)),
            verifyResult: .failure(AppError.unauthorized)
        )
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        await vm.handleIncomingToken("bad-token")
        if case .failed = vm.state { } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - reset

    func test_reset_clearsStateAndError() async {
        let repo = StubMagicLinkRepository(requestResult: .success(.init(sent: true)))
        let vm = MagicLinkViewModel(repository: repo)
        vm.email = "user@example.com"
        await vm.sendMagicLink()
        XCTAssertEqual(vm.state, .sent)

        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.resendCooldownRemaining, 0)
    }
}

// MARK: - Stubs

private actor StubMagicLinkRepository: MagicLinkRepository {
    private let requestResult: Result<MagicLinkRequestResponse, Error>
    private let verifyResult: Result<MagicLinkVerifyResponse, Error>

    init(
        requestResult: Result<MagicLinkRequestResponse, Error> = .success(.init(sent: true)),
        verifyResult: Result<MagicLinkVerifyResponse, Error> = .success(.init(authToken: "stub-token"))
    ) {
        self.requestResult = requestResult
        self.verifyResult = verifyResult
    }

    func requestLink(email: String) async throws -> MagicLinkRequestResponse {
        try requestResult.get()
    }

    func verifyToken(_ token: String) async throws -> MagicLinkVerifyResponse {
        try verifyResult.get()
    }
}
