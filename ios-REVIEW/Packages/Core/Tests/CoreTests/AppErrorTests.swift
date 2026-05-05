import XCTest
@testable import Core

final class AppErrorTests: XCTestCase {

    // MARK: — fromHttp

    func test_fromHttp_401_returnsUnauthorized() {
        let err = AppError.fromHttp(statusCode: 401)
        guard case .unauthorized = err else { return XCTFail("expected .unauthorized, got \(err)") }
    }

    func test_fromHttp_403_returnsForbidden_withCapability() {
        let err = AppError.fromHttp(statusCode: 403, message: "create_invoice")
        guard case .forbidden(let cap) = err else { return XCTFail("expected .forbidden") }
        XCTAssertEqual(cap, "create_invoice")
    }

    func test_fromHttp_404_returnsNotFound_withEntity() {
        let err = AppError.fromHttp(statusCode: 404, message: "Ticket")
        guard case .notFound(let entity) = err else { return XCTFail("expected .notFound") }
        XCTAssertEqual(entity, "Ticket")
    }

    func test_fromHttp_409_returnsConflict_withReason() {
        let err = AppError.fromHttp(statusCode: 409, message: "stale version")
        guard case .conflict(let reason) = err else { return XCTFail("expected .conflict") }
        XCTAssertEqual(reason, "stale version")
    }

    func test_fromHttp_422_returnsValidation_withFieldErrors() {
        let fields = ["email": "is invalid", "name": "is required"]
        let err = AppError.fromHttp(statusCode: 422, fieldErrors: fields)
        guard case .validation(let errs) = err else { return XCTFail("expected .validation") }
        XCTAssertEqual(errs["email"], "is invalid")
        XCTAssertEqual(errs["name"], "is required")
    }

    func test_fromHttp_422_withMessage_fallback() {
        let err = AppError.fromHttp(statusCode: 422, message: "bad data")
        guard case .validation(let errs) = err else { return XCTFail("expected .validation") }
        XCTAssertEqual(errs["_"], "bad data")
    }

    func test_fromHttp_429_returnsRateLimited_withRetryAfter() {
        let err = AppError.fromHttp(statusCode: 429, retryAfter: 30)
        guard case .rateLimited(let s) = err else { return XCTFail("expected .rateLimited") }
        XCTAssertEqual(s, 30)
    }

    func test_fromHttp_429_noRetryAfter() {
        let err = AppError.fromHttp(statusCode: 429)
        guard case .rateLimited(let s) = err else { return XCTFail("expected .rateLimited") }
        XCTAssertNil(s)
    }

    func test_fromHttp_500_returnsServer() {
        let err = AppError.fromHttp(statusCode: 500, message: "Internal")
        guard case .server(let code, let msg) = err else { return XCTFail("expected .server") }
        XCTAssertEqual(code, 500)
        XCTAssertEqual(msg, "Internal")
    }

    func test_fromHttp_418_returnsServer_noMessage() {
        let err = AppError.fromHttp(statusCode: 418)
        guard case .server(let code, let msg) = err else { return XCTFail("expected .server") }
        XCTAssertEqual(code, 418)
        XCTAssertNil(msg)
    }

    // MARK: — from(_:)

    func test_from_URLError_returnsNetwork() {
        let urlErr = URLError(.notConnectedToInternet)
        let err = AppError.from(urlErr)
        guard case .network(let u) = err else { return XCTFail("expected .network") }
        XCTAssertEqual(u?.code, .notConnectedToInternet)
    }

    func test_from_DecodingError_returnsDecoding() {
        struct Foo: Decodable {}
        // Force a decoding error
        let badData = Data("not json".utf8)
        var capturedError: Error?
        do { _ = try JSONDecoder().decode(Foo.self, from: badData) } catch { capturedError = error }
        guard let raw = capturedError else { return XCTFail("expected error") }
        let err = AppError.from(raw)
        guard case .decoding = err else { return XCTFail("expected .decoding, got \(err)") }
    }

    func test_from_AppError_passesThrough() {
        let original = AppError.offline
        let wrapped = AppError.from(original)
        guard case .offline = wrapped else { return XCTFail("expected .offline pass-through") }
    }

    func test_from_GenericError_returnsUnknown() {
        struct Sentinel: Error {}
        let err = AppError.from(Sentinel())
        guard case .unknown = err else { return XCTFail("expected .unknown") }
    }

    // MARK: — LocalizedError

    func test_errorDescription_unauthorized() {
        XCTAssertNotNil(AppError.unauthorized.errorDescription)
        XCTAssertTrue(AppError.unauthorized.errorDescription!.lowercased().contains("session"))
    }

    func test_errorDescription_offline() {
        XCTAssertNotNil(AppError.offline.errorDescription)
        XCTAssertTrue(AppError.offline.errorDescription!.lowercased().contains("offline"))
    }

    func test_errorDescription_rateLimited_withSeconds() {
        let desc = AppError.rateLimited(retryAfterSeconds: 60).errorDescription ?? ""
        XCTAssertTrue(desc.contains("60"), "should mention the retry delay")
    }

    func test_errorDescription_rateLimited_singular() {
        let desc = AppError.rateLimited(retryAfterSeconds: 1).errorDescription ?? ""
        XCTAssertTrue(desc.contains("1 second") && !desc.contains("seconds"), "should be singular")
    }

    func test_recoverySuggestion_network() {
        XCTAssertNotNil(AppError.network(underlying: nil).recoverySuggestion)
    }

    func test_recoverySuggestion_conflict() {
        XCTAssertNotNil(AppError.conflict(reason: nil).recoverySuggestion)
    }

    func test_errorDescription_persistence() {
        let desc = AppError.persistence(underlying: nil).errorDescription ?? ""
        XCTAssertTrue(desc.lowercased().contains("storage"))
    }

    func test_errorDescription_keychain() {
        let desc = AppError.keychain(status: -25300).errorDescription ?? ""
        XCTAssertTrue(desc.contains("-25300"))
    }

    func test_errorDescription_syncDeadLetter() {
        let desc = AppError.syncDeadLetter(queueId: "q1", reason: "timeout").errorDescription ?? ""
        XCTAssertTrue(desc.contains("timeout"))
    }

    func test_errorDescription_forbidden_withCapability() {
        let desc = AppError.forbidden(capability: "delete_customer").errorDescription ?? ""
        XCTAssertTrue(desc.contains("delete_customer"))
    }

    func test_errorDescription_forbidden_noCapability() {
        let desc = AppError.forbidden(capability: nil).errorDescription ?? ""
        XCTAssertTrue(desc.lowercased().contains("permission"))
    }
}
