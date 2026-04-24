import XCTest
@testable import Networking

// MARK: - RetryClassifierTests

final class RetryClassifierTests: XCTestCase {

    private let classifier = RetryClassifier()

    // MARK: HTTP 5xx — should retry

    func testHTTP500ShouldRetry() {
        let response = makeHTTPResponse(status: 500)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP502ShouldRetry() {
        let response = makeHTTPResponse(status: 502)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP503ShouldRetry() {
        let response = makeHTTPResponse(status: 503)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP504ShouldRetry() {
        let response = makeHTTPResponse(status: 504)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP599ShouldRetry() {
        let response = makeHTTPResponse(status: 599)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    // MARK: HTTP 4xx (except 429) — should NOT retry

    func testHTTP400ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 400)), .doNotRetry)
    }

    func testHTTP401ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 401)), .doNotRetry)
    }

    func testHTTP403ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 403)), .doNotRetry)
    }

    func testHTTP404ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 404)), .doNotRetry)
    }

    func testHTTP422ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 422)), .doNotRetry)
    }

    // MARK: HTTP 2xx — should NOT retry

    func testHTTP200ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 200)), .doNotRetry)
    }

    func testHTTP201ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 201)), .doNotRetry)
    }

    // MARK: HTTP 3xx — should NOT retry

    func testHTTP301ShouldNotRetry() {
        XCTAssertEqual(classifier.classify(response: makeHTTPResponse(status: 301)), .doNotRetry)
    }

    // MARK: HTTP 429 — Retry-After handling

    func testHTTP429WithRetryAfterSecondsReturnsRetryAfter() {
        let reference = Date(timeIntervalSince1970: 1_000_000)
        let response = makeHTTPResponse(status: 429, headers: ["Retry-After": "60"])
        let decision = classifier.classify(response: response, referenceDate: reference)
        XCTAssertEqual(decision, .retryAfter(60))
    }

    func testHTTP429WithRetryAfterHTTPDateReturnsRetryAfter() {
        let reference = dateFromComponents(year: 2025, month: 6, day: 15, hour: 12, minute: 0, second: 0)
        let response = makeHTTPResponse(
            status: 429,
            headers: ["Retry-After": "Sun, 15 Jun 2025 12:05:00 GMT"]
        )
        let decision = classifier.classify(response: response, referenceDate: reference)
        if case .retryAfter(let delay) = decision {
            XCTAssertEqual(delay, 300, accuracy: 2)
        } else {
            XCTFail("Expected .retryAfter, got \(decision)")
        }
    }

    func testHTTP429WithoutRetryAfterReturnsRetry() {
        let response = makeHTTPResponse(status: 429)
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP429WithZeroRetryAfterReturnsRetry() {
        let response = makeHTTPResponse(status: 429, headers: ["Retry-After": "0"])
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    func testHTTP429WithInvalidRetryAfterReturnsRetry() {
        let response = makeHTTPResponse(status: 429, headers: ["Retry-After": "not-a-value"])
        XCTAssertEqual(classifier.classify(response: response), .retry)
    }

    // MARK: URLError retryable codes

    func testURLErrorTimedOutShouldRetry() {
        let error = URLError(.timedOut)
        XCTAssertEqual(classifier.classify(error: error), .retry)
    }

    func testURLErrorNetworkConnectionLostShouldRetry() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(classifier.classify(error: error), .retry)
    }

    func testURLErrorNotConnectedToInternetShouldRetry() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(classifier.classify(error: error), .retry)
    }

    func testURLErrorDataNotAllowedShouldRetry() {
        let error = URLError(.dataNotAllowed)
        XCTAssertEqual(classifier.classify(error: error), .retry)
    }

    // MARK: URLError non-retryable codes

    func testURLErrorCancelledShouldNotRetry() {
        let error = URLError(.cancelled)
        XCTAssertEqual(classifier.classify(error: error), .doNotRetry)
    }

    func testURLErrorBadURLShouldNotRetry() {
        let error = URLError(.badURL)
        XCTAssertEqual(classifier.classify(error: error), .doNotRetry)
    }

    func testURLErrorUnknownShouldNotRetry() {
        let error = URLError(.unknown)
        XCTAssertEqual(classifier.classify(error: error), .doNotRetry)
    }

    // MARK: Non-URLError — should NOT retry

    func testGenericErrorShouldNotRetry() {
        struct SomeError: Error {}
        XCTAssertEqual(classifier.classify(error: SomeError()), .doNotRetry)
    }

    // MARK: Error + response combo — response takes priority

    func testErrorWithHTTP503ResponseShouldRetry() {
        let error = URLError(.timedOut)
        let response = makeHTTPResponse(status: 503)
        XCTAssertEqual(classifier.classify(error: error, response: response), .retry)
    }

    func testURLErrorWithHTTP200ResponseShouldNotRetry() {
        let error = URLError(.timedOut)
        let response = makeHTTPResponse(status: 200)
        XCTAssertEqual(classifier.classify(error: error, response: response), .doNotRetry)
    }

    func testURLErrorWithNoResponseUsesURLError() {
        let error = URLError(.timedOut)
        XCTAssertEqual(classifier.classify(error: error, response: nil), .retry)
    }

    // MARK: RetryDecision equatable

    func testRetryDecisionEquatable() {
        XCTAssertEqual(RetryDecision.retry, RetryDecision.retry)
        XCTAssertEqual(RetryDecision.doNotRetry, RetryDecision.doNotRetry)
        XCTAssertEqual(RetryDecision.retryAfter(30), RetryDecision.retryAfter(30))
        XCTAssertNotEqual(RetryDecision.retryAfter(30), RetryDecision.retryAfter(60))
        XCTAssertNotEqual(RetryDecision.retry, RetryDecision.doNotRetry)
    }

    // MARK: retryableURLErrorCodes constant

    func testRetryableURLErrorCodesContainsExpectedCodes() {
        XCTAssertTrue(retryableURLErrorCodes.contains(.timedOut))
        XCTAssertTrue(retryableURLErrorCodes.contains(.networkConnectionLost))
        XCTAssertTrue(retryableURLErrorCodes.contains(.notConnectedToInternet))
        XCTAssertTrue(retryableURLErrorCodes.contains(.dataNotAllowed))
        XCTAssertFalse(retryableURLErrorCodes.contains(.cancelled))
    }

    // MARK: Helpers

    private func makeHTTPResponse(
        status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func dateFromComponents(
        year: Int, month: Int, day: Int,
        hour: Int, minute: Int, second: Int
    ) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        comps.timeZone = TimeZone(abbreviation: "GMT")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
