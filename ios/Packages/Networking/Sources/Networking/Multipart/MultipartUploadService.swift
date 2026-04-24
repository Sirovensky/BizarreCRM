import Foundation
import Combine

// MARK: - MultipartUploadError

public enum MultipartUploadError: Error, Sendable, Equatable {
    /// The server returned a non-2xx status code.
    case httpError(statusCode: Int)
    /// The URLSession returned a non-HTTP response.
    case invalidResponse
    /// The response data could not be decoded to the expected type.
    case decodingFailed
}

// MARK: - UploadResult

public struct UploadResult: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

// MARK: - MultipartUploadService
//
// Standalone helper that wraps URLSession uploads.
// By default it creates a background URLSession (app-exit survival).
// Pass a custom `URLSessionConfiguration` to override — the test target
// does this to inject a URLProtocol stub.
//
// Background sessions survive app exit; the OS will deliver completion
// events via UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:…).
//
// Usage:
//   var request = URLRequest(url: uploadURL)
//   request.httpMethod = "POST"
//   request.applyMultipartForm(form, authToken: token)
//
//   let service = MultipartUploadService()
//   let (result, progress) = try await service.upload(request: request, formData: body)
//   progress.sink { print("Progress: \($0 * 100)%") }.store(in: &cancellables)

// `@unchecked Sendable`: all mutable state is confined to the URLSession
// and UploadProgressTracker, both of which are internally thread-safe.
public final class MultipartUploadService: NSObject, @unchecked Sendable {

    // MARK: Configuration

    /// Background session identifier prefix.
    public static let backgroundSessionIdentifierPrefix = "com.bizarrecrm.multipart-upload"

    // MARK: Private

    private let sessionIdentifier: String
    private let _session: URLSession
    private let progressTracker: UploadProgressTracker

    // MARK: Init

    /// Creates a service backed by a background URLSession.
    ///
    /// - Parameter sessionIdentifier: Unique identifier for the background
    ///   URLSession. Use distinct identifiers for concurrent independent uploads.
    public convenience init(
        sessionIdentifier: String = MultipartUploadService.backgroundSessionIdentifierPrefix
    ) {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpAdditionalHeaders = ["X-Origin": "ios"]
        self.init(sessionIdentifier: sessionIdentifier, configuration: config)
    }

    /// Designated init — accepts an arbitrary URLSessionConfiguration.
    /// Tests inject an ephemeral config with a URLProtocol stub registered.
    init(sessionIdentifier: String, configuration: URLSessionConfiguration) {
        self.sessionIdentifier = sessionIdentifier
        self.progressTracker = UploadProgressTracker()

        self._session = URLSession(
            configuration: configuration,
            delegate: progressTracker,
            delegateQueue: nil
        )

        super.init()
    }

    // MARK: Upload

    /// Performs a multipart upload.
    ///
    /// The body data is written to a temp file internally because background
    /// URLSession does not support `httpBody` — it requires a file upload.
    /// The temp file is deleted after the task completes.
    ///
    /// - Parameters:
    ///   - request: A URLRequest with `Content-Type: multipart/form-data; boundary=...`
    ///     already set (use `URLRequest.applyMultipartForm`).
    ///   - formData: The encoded multipart body returned from `MultipartFormData.encode()`.
    /// - Returns: An `UploadResult` plus a publisher to observe upload progress.
    public func upload(
        request: URLRequest,
        formData: Data
    ) async throws -> (result: UploadResult, progress: AnyPublisher<Double, Never>) {
        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".multipart")

        try formData.write(to: tempURL)

        let (data, response) = try await _session.upload(for: request, fromFile: tempURL)

        // Clean up temp file after upload completes.
        try? FileManager.default.removeItem(at: tempURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MultipartUploadError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw MultipartUploadError.httpError(statusCode: httpResponse.statusCode)
        }

        progressTracker.complete()

        return (
            result: UploadResult(statusCode: httpResponse.statusCode, data: data),
            progress: progressTracker.progressPublisher
        )
    }

    // MARK: Progress

    /// Direct access to the progress publisher without going through upload().
    public var progressPublisher: AnyPublisher<Double, Never> {
        progressTracker.progressPublisher
    }
}
