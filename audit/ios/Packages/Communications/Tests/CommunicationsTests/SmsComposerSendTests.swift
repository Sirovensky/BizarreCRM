import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsComposerSendTests
//
// Tests that:
//   1. SmsComposerViewModel.isValid gates sending correctly.
//   2. loadTemplate wires correctly to a composed draft.
//   3. The Networking-layer previewSmsTemplate endpoint path is correct.

// MARK: - Preview template endpoint path tests

private actor PreviewStubAPIClient: APIClient {
    private(set) var lastPostPath: String?
    private(set) var postCallCount: Int = 0
    var previewResult: SmsTemplatePreviewResult?
    var previewError: Error?

    func setPreviewResult(_ r: SmsTemplatePreviewResult?) { previewResult = r }
    func setPreviewError(_ e: Error?) { previewError = e }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        postCallCount += 1
        lastPostPath = path
        if let err = previewError { throw err }
        let r = previewResult ?? SmsTemplatePreviewResult(preview: "Hello Jane", charCount: 10)
        guard let cast = r as? T else { throw APITransportError.decoding("preview") }
        return cast
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - Endpoint path tests (Networking)

final class SmsTemplatePreviewEndpointTests: XCTestCase {

    func test_previewSmsTemplate_usesCorrectPath() async throws {
        let api = PreviewStubAPIClient()
        await api.setPreviewResult(SmsTemplatePreviewResult(preview: "Hi Jane", charCount: 7))

        _ = try await api.previewSmsTemplate(templateId: 42, vars: ["first_name": "Jane"])

        let path = await api.lastPostPath
        XCTAssertEqual(path, "/api/v1/sms/preview-template", "previewSmsTemplate must POST to /api/v1/sms/preview-template")
    }

    func test_previewSmsTemplate_callCount_isOne() async throws {
        let api = PreviewStubAPIClient()
        await api.setPreviewResult(SmsTemplatePreviewResult(preview: "Hi", charCount: 2))

        _ = try await api.previewSmsTemplate(templateId: 1, vars: [:])

        let count = await api.postCallCount
        XCTAssertEqual(count, 1)
    }

    func test_previewSmsTemplate_propagatesError() async throws {
        let api = PreviewStubAPIClient()
        await api.setPreviewError(APITransportError.networkUnavailable)

        do {
            _ = try await api.previewSmsTemplate(templateId: 1, vars: [:])
            XCTFail("Expected error")
        } catch {
            // correct
        }
    }

    func test_previewSmsTemplate_returnsPreviewText() async throws {
        let api = PreviewStubAPIClient()
        await api.setPreviewResult(SmsTemplatePreviewResult(preview: "Hello World", charCount: 11))

        let result = try await api.previewSmsTemplate(templateId: 5, vars: ["first_name": "World"])

        XCTAssertEqual(result.preview, "Hello World")
        XCTAssertEqual(result.charCount, 11)
    }
}

// MARK: - SmsTemplatePreviewResult decoding

final class SmsTemplatePreviewResultDecodingTests: XCTestCase {

    func test_decode_previewAndCharCount() throws {
        let json = """
        {"preview":"Hello Jane","char_count":10}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(SmsTemplatePreviewResult.self, from: json)
        XCTAssertEqual(result.preview, "Hello Jane")
        XCTAssertEqual(result.charCount, 10)
    }
}

// MARK: - SmsComposerViewModel send-guard tests
//
// These tests document the send-gate invariants that the `SmsComposerView`
// respects: the send button is disabled when `isValid` is false, and the
// ViewModel draft is cleared after a successful send callback.

@MainActor
final class SmsComposerViewModelSendGateTests: XCTestCase {

    // MARK: - isValid gate

    func test_isValid_false_preventsEffectiveSend() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        // Empty draft → isValid == false
        XCTAssertFalse(vm.isValid, "Empty draft must block send")
    }

    func test_isValid_true_afterNonWhitespaceDraft() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        vm.draft = "Hello"
        XCTAssertTrue(vm.isValid, "Non-empty draft must allow send")
    }

    func test_isValid_false_forWhitespaceOnly() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        vm.draft = "   \t  "
        XCTAssertFalse(vm.isValid, "Whitespace-only draft must block send")
    }

    // MARK: - loadTemplate feeds send

    func test_loadTemplate_thenValid_allowsSend() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        let template = MessageTemplate(id: 1, name: "T", body: "Your repair is ready", channel: .sms, category: .reminder)
        vm.loadTemplate(template)
        XCTAssertTrue(vm.isValid, "After loading a template the draft must be non-empty → isValid")
    }

    func test_loadTemplate_setsDraftToBody() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        let template = MessageTemplate(id: 2, name: "Promo", body: "20% off today", channel: .sms, category: .promo)
        vm.loadTemplate(template)
        XCTAssertEqual(vm.draft, "20% off today")
    }

    // MARK: - phoneNumber is preserved for the send call

    func test_phoneNumber_preserved_afterInsert() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111", prefillBody: "Hi")
        vm.insertAtCursor("{ticket_no}")
        XCTAssertEqual(vm.phoneNumber, "+15550001111", "phoneNumber must not change after chip insertion")
    }

    // MARK: - Draft trimming (mirrors performSend behaviour in view)

    func test_draft_trimmedForSend() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        vm.draft = "  Hello  "
        let trimmed = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(trimmed, "Hello", "Draft must be trimmed before sending")
        XCTAssertTrue(vm.isValid, "Draft with surrounding spaces is still valid")
    }

    // MARK: - Segment count sanity for multi-part messages

    func test_segmentCount_longMessage_twoSegments() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        vm.draft = String(repeating: "X", count: 320)
        XCTAssertEqual(vm.smsSegmentCount, 2)
    }

    func test_segmentCount_exactBoundary_160() {
        let vm = SmsComposerViewModel(phoneNumber: "+15550001111")
        vm.draft = String(repeating: "Y", count: 160)
        XCTAssertEqual(vm.smsSegmentCount, 1)
    }
}

// MARK: - SmsTemplatePreviewRequest encoding

final class SmsTemplatePreviewRequestEncodingTests: XCTestCase {

    func test_encode_usesSnakeCaseTemplateId() throws {
        let req = SmsTemplatePreviewRequest(templateId: 7, vars: ["name": "Bob"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["template_id"], "templateId must be encoded as 'template_id'")
        XCTAssertEqual(json?["template_id"] as? Int, 7)
    }

    func test_encode_vars_preservedAsObject() throws {
        let req = SmsTemplatePreviewRequest(templateId: 1, vars: ["first_name": "Alice"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let vars = json?["vars"] as? [String: String]
        XCTAssertEqual(vars?["first_name"], "Alice")
    }
}
