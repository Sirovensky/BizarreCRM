import XCTest
@testable import Core

// §63 — Unit tests for ErrorStateMapper.

final class ErrorStateMapperTests: XCTestCase {

    // MARK: — map(AppError)

    func testMap_appError_network() {
        let urlErr = URLError(.timedOut)
        XCTAssertEqual(ErrorStateMapper.map(AppError.network(underlying: urlErr)), .network)
    }

    func testMap_appError_networkNilUnderlying() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.network(underlying: nil)), .network)
    }

    func testMap_appError_server() {
        let result = ErrorStateMapper.map(AppError.server(statusCode: 503, message: "down"))
        XCTAssertEqual(result, .server(status: 503, message: "down"))
    }

    func testMap_appError_server_nilMessage() {
        let result = ErrorStateMapper.map(AppError.server(statusCode: 500, message: nil))
        XCTAssertEqual(result, .server(status: 500, message: nil))
    }

    func testMap_appError_envelope() {
        let result = ErrorStateMapper.map(AppError.envelope(reason: "bad json"))
        XCTAssertEqual(result, .server(status: 200, message: "The server response was malformed."))
    }

    func testMap_appError_decoding() {
        let result = ErrorStateMapper.map(AppError.decoding(type: "Customer", underlying: nil))
        XCTAssertEqual(result, .server(status: 200, message: "Could not read the server response."))
    }

    func testMap_appError_unauthorized() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.unauthorized), .unauthorized)
    }

    func testMap_appError_forbidden() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.forbidden(capability: "admin")), .forbidden)
    }

    func testMap_appError_notFound() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.notFound(entity: "Ticket")), .notFound)
    }

    func testMap_appError_conflict() {
        let result = ErrorStateMapper.map(AppError.conflict(reason: "stale"))
        XCTAssertEqual(result, .server(status: 409, message: "stale"))
    }

    func testMap_appError_conflict_nilReason() {
        let result = ErrorStateMapper.map(AppError.conflict(reason: nil))
        XCTAssertEqual(result, .server(status: 409, message: "A conflict occurred."))
    }

    func testMap_appError_rateLimited_withSeconds() {
        let result = ErrorStateMapper.map(AppError.rateLimited(retryAfterSeconds: 60))
        XCTAssertEqual(result, .rateLimited(retrySeconds: 60))
    }

    func testMap_appError_rateLimited_nil() {
        let result = ErrorStateMapper.map(AppError.rateLimited(retryAfterSeconds: nil))
        XCTAssertEqual(result, .rateLimited(retrySeconds: nil))
    }

    func testMap_appError_validation() {
        let result = ErrorStateMapper.map(AppError.validation(fieldErrors: ["email": "invalid"]))
        if case .validation(let fields) = result {
            XCTAssertEqual(fields, ["email"])
        } else {
            XCTFail("Expected .validation, got \(result)")
        }
    }

    func testMap_appError_offline() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.offline), .offline)
    }

    func testMap_appError_syncDeadLetter() {
        let result = ErrorStateMapper.map(AppError.syncDeadLetter(queueId: "q1", reason: "too many retries"))
        XCTAssertEqual(result, .server(status: 0, message: "too many retries"))
    }

    func testMap_appError_persistence() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.persistence(underlying: nil)), .unknown)
    }

    func testMap_appError_keychain() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.keychain(status: -25300)), .unknown)
    }

    func testMap_appError_cancelled() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.cancelled), .unknown)
    }

    func testMap_appError_unknown() {
        XCTAssertEqual(ErrorStateMapper.map(AppError.unknown(underlying: nil)), .unknown)
    }

    // MARK: — map(URLError)

    func testMap_urlError_notConnected() {
        let err = URLError(.notConnectedToInternet)
        XCTAssertEqual(ErrorStateMapper.map(err), .offline)
    }

    func testMap_urlError_networkConnectionLost() {
        let err = URLError(.networkConnectionLost)
        XCTAssertEqual(ErrorStateMapper.map(err), .offline)
    }

    func testMap_urlError_dataNotAllowed() {
        let err = URLError(.dataNotAllowed)
        XCTAssertEqual(ErrorStateMapper.map(err), .offline)
    }

    func testMap_urlError_timeout() {
        let err = URLError(.timedOut)
        XCTAssertEqual(ErrorStateMapper.map(err), .network)
    }

    func testMap_urlError_cannotConnect() {
        let err = URLError(.cannotConnectToHost)
        XCTAssertEqual(ErrorStateMapper.map(err), .network)
    }

    // MARK: — map(Error) — generic

    func testMap_genericError_AppError_passthrough() {
        let error: Error = AppError.offline
        XCTAssertEqual(ErrorStateMapper.map(error), .offline)
    }

    func testMap_genericError_URLError_passthrough() {
        let error: Error = URLError(.notConnectedToInternet)
        XCTAssertEqual(ErrorStateMapper.map(error), .offline)
    }

    func testMap_genericError_nsError_urlDomain() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(ErrorStateMapper.map(error), .offline)
    }

    func testMap_genericError_unknown_type() {
        struct RandomError: Error {}
        XCTAssertEqual(ErrorStateMapper.map(RandomError()), .unknown)
    }

    // MARK: — mapHTTP

    func testMapHTTP_200_returnsUnknown() {
        // 2xx should not be passed as an error — mapper returns .unknown
        XCTAssertEqual(ErrorStateMapper.mapHTTP(statusCode: 200), .unknown)
    }

    func testMapHTTP_401() {
        XCTAssertEqual(ErrorStateMapper.mapHTTP(statusCode: 401), .unauthorized)
    }

    func testMapHTTP_403() {
        XCTAssertEqual(ErrorStateMapper.mapHTTP(statusCode: 403), .forbidden)
    }

    func testMapHTTP_404() {
        XCTAssertEqual(ErrorStateMapper.mapHTTP(statusCode: 404), .notFound)
    }

    func testMapHTTP_422_withMessage() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 422, message: "invalid email")
        if case .validation(let fields) = result {
            XCTAssertEqual(fields, ["invalid email"])
        } else {
            XCTFail("Expected .validation, got \(result)")
        }
    }

    func testMapHTTP_422_noMessage() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 422)
        if case .validation(let fields) = result {
            XCTAssertTrue(fields.isEmpty)
        } else {
            XCTFail("Expected .validation, got \(result)")
        }
    }

    func testMapHTTP_429_withRetryAfter() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 429, retryAfterSeconds: 45)
        XCTAssertEqual(result, .rateLimited(retrySeconds: 45))
    }

    func testMapHTTP_429_noRetryAfter() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 429)
        XCTAssertEqual(result, .rateLimited(retrySeconds: nil))
    }

    func testMapHTTP_500() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 500, message: "Internal Server Error")
        XCTAssertEqual(result, .server(status: 500, message: "Internal Server Error"))
    }

    func testMapHTTP_503_noMessage() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 503)
        XCTAssertEqual(result, .server(status: 503, message: nil))
    }

    func testMapHTTP_409_genericServer() {
        let result = ErrorStateMapper.mapHTTP(statusCode: 409, message: "conflict")
        XCTAssertEqual(result, .server(status: 409, message: "conflict"))
    }
}
