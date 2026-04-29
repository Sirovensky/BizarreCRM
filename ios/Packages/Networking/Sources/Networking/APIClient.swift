import Foundation
import Core

public protocol APIClient: Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func delete(_ path: String) async throws

    /// Raw unwrapped envelope — for endpoints where you want the message (e.g. SERVER validation).
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T>

    func setAuthToken(_ token: String?) async
    func setBaseURL(_ url: URL?) async
    func currentBaseURL() async -> URL?
    func setRefresher(_ refresher: AuthSessionRefresher?) async

    /// Run an authenticated raw data request (for CSV/PDF downloads etc.).
    /// The actor stamps `Authorization: Bearer <token>` and routes through
    /// the same configured `URLSession` as the JSON path, so SPKI pinning
    /// + standard headers (`X-Origin`, gzip/br) + timeouts apply. Returns
    /// the response body and metadata. Throws on transport / non-2xx.
    func authedDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse)

    /// §1.1 — Multipart upload helper for photos, receipts, avatars.
    ///
    /// POSTs `data` as a `multipart/form-data` body to `path` (resolved
    /// against `baseURL`). The implementation in `APIClientImpl` uses a
    /// background `URLSession` so uploads survive app exit; the OS will
    /// deliver completion to `application(_:handleEventsForBackgroundURLSession:…)`.
    ///
    /// - Parameters:
    ///   - data: Raw bytes of the file part.
    ///   - path: Relative path appended to `baseURL`, or absolute URL.
    ///   - fileName: `Content-Disposition` filename for the file part.
    ///   - mimeType: Content-Type for the file part (e.g. `image/jpeg`).
    ///   - fields: Form fields appended before the file part.
    /// - Returns: Raw response body data on 2xx.
    /// - Throws: `APITransportError.httpStatus` on non-2xx; `.noBaseURL`
    ///   if `baseURL` isn't set.
    func upload(
        _ data: Data,
        to path: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> Data
}

public extension APIClient {
    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }

    /// Default implementation so existing test stubs (which conform to the
    /// protocol but don't exercise upload) continue to compile. Real clients
    /// (`APIClientImpl`) override this with a background-URLSession path.
    func upload(
        _ data: Data,
        to path: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> Data {
        throw APITransportError.notImplemented
    }
}

public actor APIClientImpl: APIClient {
    private var baseURL: URL?
    private var authToken: String?
    private var refresher: AuthSessionRefresher?
    private var refreshInFlight: Task<Bool, Error>?
    private let pinnedSPKIBase64: Set<String>

    // §1.1 — Background URLSession for multipart uploads. Lazy + cached
    // per-process: `URLSessionConfiguration.background(withIdentifier:)`
    // throws if you create two sessions with the same identifier in one
    // process. This survives app exit; the OS will deliver completion
    // events via `application(_:handleEventsForBackgroundURLSession:…)`.
    public static let backgroundUploadSessionIdentifier = "com.bizarrecrm.upload"
    public static let backgroundUploadSharedContainerIdentifier = "group.com.bizarrecrm"
    private var _uploadSession: URLSession?

    // Lazy — deferred until the first network call so app launch isn't
    // blocked by URLSession + delegate construction.
    private var _session: URLSession?
    private var session: URLSession {
        if let s = _session { return s }
        let cfg = URLSessionConfiguration.default
        // §29.7 Networking — HTTP/2 default on iOS; we additionally:
        //   • Disable URLCache for data calls (GRDB / repo layer is the cache).
        //   • 15 s per-request, 5 min per-resource (was 30 s) — supports
        //     longer uploads / chunked PDFs while keeping fast-fail on UI calls.
        //   • Keep-alive pool of 6 connections per host (HTTP/2 multiplexes).
        //   • Allow cellular for self-hosted tenants.
        //   • Accept gzip + brotli compression (URLSession decompresses).
        cfg.timeoutIntervalForRequest = 15          // §29.7: 15 s default (was 30)
        cfg.timeoutIntervalForResource = 300        // 5 min outer resource limit
        cfg.waitsForConnectivity = true
        cfg.httpShouldUsePipelining = false         // HTTP/2 multiplexes; pipelining not needed
        cfg.httpMaximumConnectionsPerHost = 6       // keep-alive pool; enough for H/2 streams
        cfg.urlCache = nil                          // data calls handled by repo layer (§29.7)
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.allowsCellularAccess = true
        cfg.allowsConstrainedNetworkAccess = true   // cautious cellular is fine for API
        cfg.allowsExpensiveNetworkAccess = true     // cellular is OK; uploads respect §20.6
        cfg.httpAdditionalHeaders = [
            "X-Origin": "ios",
            "Accept": "application/json",
            // §29.7 Compression — request gzip and brotli; URLSession decompresses transparently.
            "Accept-Encoding": "gzip, br"
        ]
        let s: URLSession
        if pinnedSPKIBase64.isEmpty {
            s = URLSession(configuration: cfg)
        } else {
            let delegate = PinnedURLSessionDelegate(pinnedSPKIBase64: pinnedSPKIBase64)
            s = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        }
        _session = s
        return s
    }

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(initialBaseURL: URL? = nil, pinnedSPKIBase64: Set<String> = []) {
        self.baseURL = initialBaseURL
        self.pinnedSPKIBase64 = pinnedSPKIBase64

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        // Encoder sends keys as-declared (camelCase by default). The server
        // mixes conventions per endpoint — /signup reads snake_case, /auth
        // endpoints read camelCase — so we can't blanket-convert. Each
        // request struct declares explicit CodingKeys when it needs snake.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func setAuthToken(_ token: String?) { self.authToken = token }
    public func setBaseURL(_ url: URL?) { self.baseURL = url }
    public func currentBaseURL() -> URL? { baseURL }
    public func setRefresher(_ refresher: AuthSessionRefresher?) { self.refresher = refresher }

    /// §1.1 — Multipart upload over a background URLSession. Builds a
    /// multipart/form-data body (fields first, file part last with a
    /// stable boundary), stamps Authorization from the actor's `authToken`,
    /// resolves `path` against `baseURL`, and POSTs via a *background*
    /// URLSession so the upload survives app exit.
    ///
    /// Background sessions don't accept `httpBody` directly — they require
    /// a file upload — so the encoded body is staged to a temp file and
    /// passed to `URLSession.upload(for:fromFile:)`. The temp file is
    /// removed after the task completes (success or failure).
    public func upload(
        _ data: Data,
        to path: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> Data {
        guard let base = baseURL else { throw APITransportError.noBaseURL }
        let url: URL
        if path.hasPrefix("http") {
            guard let u = URL(string: path) else { throw APITransportError.invalidResponse }
            url = u
        } else {
            url = base.appendingPathComponent(path)
        }

        var form = MultipartFormData(boundary: UUID().uuidString)
        for (key, value) in fields {
            form.appendField(name: key, value: value)
        }
        // File part last per §1.1 contract.
        form.appendFile(
            name: "file",
            filename: fileName,
            mimeType: mimeType,
            data: data
        )
        let (body, contentTypeValue) = form.encode()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentTypeValue, forHTTPHeaderField: "Content-Type")
        req.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        if let origin = Self.origin(for: url) {
            req.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".multipart-upload")
        try body.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let s = uploadSession
        let (responseData, response) = try await s.upload(for: req, fromFile: tempURL)
        guard let http = response as? HTTPURLResponse else {
            throw APITransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: responseData, encoding: .utf8)
            throw APITransportError.httpStatus(http.statusCode, message: message)
        }
        return responseData
    }

    /// Lazy + cached background URLSession for multipart uploads.
    /// `delegateQueue: nil` lets URLSession pick its own serial queue;
    /// `sharedContainerIdentifier` makes the staged temp data accessible
    /// to extensions in the same app group.
    private var uploadSession: URLSession {
        if let s = _uploadSession { return s }
        let cfg = URLSessionConfiguration.background(
            withIdentifier: APIClientImpl.backgroundUploadSessionIdentifier
        )
        cfg.sharedContainerIdentifier = APIClientImpl.backgroundUploadSharedContainerIdentifier
        cfg.isDiscretionary = false
        cfg.sessionSendsLaunchEvents = true
        cfg.allowsCellularAccess = true
        cfg.httpAdditionalHeaders = [
            "X-Origin": "ios",
            "Accept": "application/json"
        ]
        let s = URLSession(configuration: cfg, delegate: nil, delegateQueue: nil)
        _uploadSession = s
        return s
    }

    public func authedDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8)
            throw APITransportError.httpStatus(http.statusCode, message: message)
        }
        return (data, response)
    }

    public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "GET", query: query, body: nil as String?), as: T.self))
    }

    public func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        try await perform(request(path, method: "GET", query: query, body: nil as String?), as: T.self)
    }

    public func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "POST", query: nil, body: body), as: T.self))
    }

    public func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "PUT", query: nil, body: body), as: T.self))
    }

    public func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "PATCH", query: nil, body: body), as: T.self))
    }

    public func delete(_ path: String) async throws {
        _ = try await perform(request(path, method: "DELETE", query: nil, body: nil as String?), as: EmptyPayload.self)
    }

    private func request<B: Encodable>(_ path: String, method: String, query: [URLQueryItem]?, body: B?) throws -> URLRequest {
        guard let base = baseURL else { throw APITransportError.noBaseURL }

        let absolute = path.hasPrefix("http") ? URL(string: path)! : base.appendingPathComponent(path)
        var comps = URLComponents(url: absolute, resolvingAgainstBaseURL: false)
        comps?.queryItems = query
        guard let url = comps?.url else { throw APITransportError.invalidResponse }

        var req = URLRequest(url: url)
        req.httpMethod = method

        // Server (SEC-H7 in packages/server/src/index.ts:931–948) rejects API
        // requests without an Origin header in production. Browsers set it
        // automatically; native apps don't. Derive Origin from whichever URL
        // the request is going to so it matches the tenant/cloud domain.
        if let origin = Self.origin(for: url) {
            req.setValue(origin, forHTTPHeaderField: "Origin")
        }

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    private static func origin(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private func perform<T: Decodable & Sendable>(_ req: URLRequest, as type: T.Type) async throws -> APIResponse<T> {
        // §1.1 — Rate-limit before the first attempt (reads bucket; throws on sustained overload).
        if let host = req.url?.host {
            try await RateLimiters.perHost.acquireIfEnabled(host: host)
        }

        // §1.1 — Retry with jitter on 5xx / timeout / connection-lost.
        // The inner closure calls performOnce which handles 401-refresh internally.
        let executor = RetryExecutor(policy: .default)
        return try await executor.execute {
            try await self.performOnce(req, as: T.self, allowRetryAfterRefresh: true)
        }
    }

    private func performOnce<T: Decodable & Sendable>(
        _ req: URLRequest,
        as _: T.Type,
        allowRetryAfterRefresh: Bool
    ) async throws -> APIResponse<T> {
        let hadAuth = req.value(forHTTPHeaderField: "Authorization") != nil
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APITransportError.invalidResponse }

        // §2.11 refresh-and-retry. 401 on an authenticated call → try the
        // refresher once, update the Authorization header, replay the
        // original request. Only on refresh failure do we post
        // SessionEvents.sessionRevoked and drop the user to Login.
        if http.statusCode == 401, hadAuth {
            if allowRetryAfterRefresh, refresher != nil {
                let refreshed = await refreshSessionOnce()
                if refreshed, let newToken = authToken {
                    var retry = req
                    retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    return try await performOnce(retry, as: T.self, allowRetryAfterRefresh: false)
                }
            }
            SessionEvents.post(.sessionRevoked)
        }

        // §1.1 — Apply Retry-After to the per-host bucket so concurrent waiters
        // also pause. This mirrors what RetryClassifier does for the executor.
        if http.statusCode == 429,
           let retryAfterValue = http.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Int(retryAfterValue),
           let host = req.url?.host {
            await RateLimiters.perHost.applyRetryAfter(seconds, host: host)
        }

        do {
            let envelope = try decoder.decode(APIResponse<T>.self, from: data)
            if !(200..<300).contains(http.statusCode) {
                // Surface the server's message verbatim. 401 during login means
                // "Invalid credentials" — the caller (LoginFlow) shouldn't see
                // a hardcoded "session expired" string here.
                throw APITransportError.httpStatus(http.statusCode, message: envelope.message)
            }
            return envelope
        } catch let decodingError as DecodingError {
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)
                throw APITransportError.httpStatus(http.statusCode, message: body)
            }
            throw APITransportError.decoding("\(decodingError)")
        }
    }

    /// Single-flight refresh. Concurrent 401s queue behind the same task.
    /// Returns `true` if the APIClient's authToken was rotated to a new value.
    ///
    /// Contract: refresher persists to TokenStore AND returns the new
    /// `(accessToken, refreshToken)`. We update `self.authToken` inline
    /// so the retry uses the new bearer.
    private func refreshSessionOnce() async -> Bool {
        if let inFlight = refreshInFlight {
            return (try? await inFlight.value) ?? false
        }
        guard let refresher else { return false }
        let task = Task<Bool, Error> { [refresher, weak self] in
            let pair = try await refresher.refresh()
            guard !pair.accessToken.isEmpty else { return false }
            await self?.applyRefreshed(token: pair.accessToken)
            return true
        }
        refreshInFlight = task
        let ok = (try? await task.value) ?? false
        refreshInFlight = nil
        return ok
    }

    private func applyRefreshed(token: String) {
        self.authToken = token
    }

    private func unwrap<T: Decodable & Sendable>(_ envelope: APIResponse<T>) throws -> T {
        guard envelope.success, let payload = envelope.data else {
            throw APITransportError.envelopeFailure(message: envelope.message)
        }
        return payload
    }
}

private struct EmptyPayload: Decodable, Sendable {}
