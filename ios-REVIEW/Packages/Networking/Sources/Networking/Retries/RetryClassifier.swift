import Foundation

// MARK: - RetryDecision

/// What the classifier decided for a given error/response.
public enum RetryDecision: Sendable, Equatable {
    /// Retry immediately (or after the standard backoff).
    case retry
    /// Retry after the specified delay (e.g. from Retry-After header).
    case retryAfter(TimeInterval)
    /// Do not retry — surface the error to the caller.
    case doNotRetry
}

// MARK: - RetryClassifier

/// Pure value type that decides whether a failed request should be retried.
///
/// Retryable conditions:
/// - HTTP 5xx status codes
/// - HTTP 429 Too Many Requests (honours `Retry-After` header when present)
/// - `URLError` with codes: `.timedOut`, `.networkConnectionLost`,
///   `.notConnectedToInternet`, `.dataNotAllowed`
///
/// All other errors are classified as `.doNotRetry`.
public struct RetryClassifier: Sendable {

    // MARK: Init

    public init() {}

    // MARK: Public API

    /// Classify an error (and optional HTTP response) into a `RetryDecision`.
    ///
    /// - Parameters:
    ///   - error: The thrown error from the request.
    ///   - response: Optional `HTTPURLResponse` that accompanied the error/result.
    ///   - referenceDate: Reference for parsing HTTP-date Retry-After values. Defaults to `Date()`.
    public func classify(
        error: Error,
        response: HTTPURLResponse? = nil,
        referenceDate: Date = Date()
    ) -> RetryDecision {
        // 1. HTTP-level classification (takes priority when we have a response)
        if let httpResponse = response {
            return classifyHTTP(httpResponse, referenceDate: referenceDate)
        }

        // 2. URL-level classification
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        return .doNotRetry
    }

    /// Classify a completed HTTP response (no thrown error) — useful for callers
    /// that inspect the response status themselves.
    ///
    /// - Parameters:
    ///   - response: The HTTP response to classify.
    ///   - referenceDate: Reference for parsing HTTP-date Retry-After values.
    public func classify(
        response: HTTPURLResponse,
        referenceDate: Date = Date()
    ) -> RetryDecision {
        classifyHTTP(response, referenceDate: referenceDate)
    }

    // MARK: Private helpers

    private func classifyHTTP(
        _ response: HTTPURLResponse,
        referenceDate: Date
    ) -> RetryDecision {
        let status = response.statusCode

        switch status {
        case 429:
            // Honour Retry-After if present
            if let header = response.value(forHTTPHeaderField: "Retry-After"),
               let delay = RetryAfterParser.parse(header, referenceDate: referenceDate),
               delay > 0 {
                return .retryAfter(delay)
            }
            // 429 without Retry-After: still retry but use standard backoff
            return .retry

        case 500...599:
            return .retry

        default:
            return .doNotRetry
        }
    }

    private func classifyURLError(_ error: URLError) -> RetryDecision {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dataNotAllowed:
            return .retry

        default:
            return .doNotRetry
        }
    }
}

// MARK: - RetryableURLErrorCodes

/// Set of `URLError.Code` values that `RetryClassifier` treats as retryable.
/// Exposed for documentation / external inspection.
public let retryableURLErrorCodes: Set<URLError.Code> = [
    .timedOut,
    .networkConnectionLost,
    .notConnectedToInternet,
    .dataNotAllowed,
]
