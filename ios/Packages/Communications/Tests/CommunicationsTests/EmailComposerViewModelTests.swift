import XCTest
@testable import Communications
import Networking
import Core

// MARK: - EmailComposerViewModelTests
// TDD: written before EmailComposerViewModel was implemented.

@MainActor
final class EmailComposerViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        toEmail: String = "customer@example.com",
        prefillSubject: String = "",
        prefillBody: String = ""
    ) -> EmailComposerViewModel {
        let api = StubEmailAPIClient()
        return EmailComposerViewModel(
            toEmail: toEmail,
            prefillSubject: prefillSubject,
            prefillBody: prefillBody,
            api: api
        )
    }

    private func makeSUTWithSendError() -> (EmailComposerViewModel, StubEmailAPIClient) {
        let api = StubEmailAPIClient(sendError: URLError(.timedOut))
        let vm = EmailComposerViewModel(toEmail: "a@b.com", prefillSubject: "S", prefillBody: "B", api: api)
        return (vm, api)
    }

    private func makeSUTWithSendSuccess() -> (EmailComposerViewModel, StubEmailAPIClient) {
        let api = StubEmailAPIClient()
        let vm = EmailComposerViewModel(toEmail: "a@b.com", prefillSubject: "S", prefillBody: "B", api: api)
        return (vm, api)
    }

    // MARK: - Initial state

    func test_init_toEmail_prefilled() {
        let sut = makeSUT(toEmail: "test@example.com")
        XCTAssertEqual(sut.toEmail, "test@example.com")
    }

    func test_init_subject_prefilled() {
        let sut = makeSUT(prefillSubject: "Your invoice")
        XCTAssertEqual(sut.subject, "Your invoice")
    }

    func test_init_body_prefilled() {
        let sut = makeSUT(prefillBody: "Body text")
        XCTAssertEqual(sut.body, "Body text")
    }

    func test_init_isSending_false() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isSending)
    }

    func test_init_errorMessage_nil() {
        let sut = makeSUT()
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - isValid

    func test_isValid_trueWhenToAndSubjectAndBodyNonEmpty() {
        let sut = makeSUT(toEmail: "a@b.com", prefillSubject: "Sub", prefillBody: "Body")
        XCTAssertTrue(sut.isValid)
    }

    func test_isValid_falseWhenToEmpty() {
        let sut = makeSUT(toEmail: "")
        sut.subject = "Sub"
        sut.body = "Body"
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_falseWhenSubjectEmpty() {
        let sut = makeSUT(toEmail: "a@b.com")
        sut.subject = ""
        sut.body = "Body"
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_falseWhenBodyEmpty() {
        let sut = makeSUT(toEmail: "a@b.com")
        sut.subject = "Sub"
        sut.body = ""
        XCTAssertFalse(sut.isValid)
    }

    // MARK: - Cursor insert

    func test_insertAtCursor_appendsWhenNoCursor() {
        let sut = makeSUT()
        sut.body = "Hello"
        sut.insertAtBodyCursor("{first_name}")
        XCTAssertEqual(sut.body, "Hello{first_name}")
    }

    func test_insertAtCursor_insertsAtOffset() {
        let sut = makeSUT()
        sut.body = "Hi !"
        sut.bodyCursorOffset = 3
        sut.insertAtBodyCursor("{first_name}")
        XCTAssertEqual(sut.body, "Hi {first_name}!")
    }

    // MARK: - Load template

    func test_loadTemplate_setsSubjectAndBody() {
        let sut = makeSUT()
        let template = EmailTemplate(
            id: 1, name: "T", subject: "Invoice {ticket_no}",
            htmlBody: "<p>Amount {total}</p>", plainBody: "Amount {total}",
            category: .reminder, dynamicVars: []
        )
        sut.loadTemplate(template)
        XCTAssertEqual(sut.subject, "Invoice {ticket_no}")
        XCTAssertEqual(sut.body, "<p>Amount {total}</p>")
    }

    // MARK: - Live HTML preview

    func test_htmlPreview_substitutesVars() {
        let sut = makeSUT()
        sut.body = "<p>Hi {first_name}</p>"
        let preview = sut.htmlPreview
        XCTAssertFalse(preview.contains("{first_name}"))
        XCTAssertTrue(preview.contains("Hi "))
    }

    // MARK: - Send success

    func test_send_success_setsSentTrue() async {
        let (sut, _) = makeSUTWithSendSuccess()
        await sut.send()
        XCTAssertTrue(sut.didSend)
        XCTAssertNil(sut.errorMessage)
    }

    func test_send_success_isSendingFalse_afterwards() async {
        let (sut, _) = makeSUTWithSendSuccess()
        await sut.send()
        XCTAssertFalse(sut.isSending)
    }

    // MARK: - Send error

    func test_send_error_setsErrorMessage() async {
        let (sut, _) = makeSUTWithSendError()
        await sut.send()
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.didSend)
    }

    func test_send_error_isSendingFalse_afterwards() async {
        let (sut, _) = makeSUTWithSendError()
        await sut.send()
        XCTAssertFalse(sut.isSending)
    }

    // MARK: - Known chip vars

    func test_knownVars_containsRequiredChips() {
        let required = ["{first_name}", "{ticket_no}", "{total}", "{due_date}", "{tech_name}", "{appointment_time}", "{shop_name}"]
        for v in required {
            XCTAssertTrue(EmailComposerViewModel.knownVars.contains(v), "Missing chip: \(v)")
        }
    }
}

// MARK: - Stub API

private actor StubEmailAPIClient: APIClient {
    let sendError: Error?

    init(sendError: Error? = nil) {
        self.sendError = sendError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = sendError { throw err }
        // Return a stub EmailSendResponse
        if let r = EmailSendAck() as? T { return r }
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
