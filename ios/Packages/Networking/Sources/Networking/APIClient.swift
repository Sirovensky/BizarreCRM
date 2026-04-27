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
}

public extension APIClient {
    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }
}

public actor APIClientImpl: APIClient {
    private var baseURL: URL?
    private var authToken: String?
    private var refresher: AuthSessionRefresher?
    private var refreshInFlight: Task<Bool, Error>?
    private let pinnedSPKIBase64: Set<String>

    // Lazy — deferred until the first network call so app launch isn't
    // blocked by URLSession + delegate construction.
    private var _session: URLSession?
    private var session: URLSession {
        if let s = _session { return s }
        let cfg = URLSessionConfiguration.default
        // §29.7 — HTTP/2 is the default on iOS; we additionally:
        //   • Disable URLCache for data calls (GRDB is the cache, not NSURLCache).
        //   • Force 15s per-request + 30s per-resource timeouts.
        //   • Allow cellular (tenant may be self-hosted, not wi-fi-only).
        //   • Accept gzip + brotli compression.
        cfg.timeoutIntervalForRequest = 15      // §29.7 15s default
        cfg.timeoutIntervalForResource = 30     // keep-alive max
        cfg.waitsForConnectivity = true
        cfg.urlCache = nil                      // GRDB owns caching — not NSURLCache
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.allowsCellularAccess = true
        cfg.allowsConstrainedNetworkAccess = true   // cautious cellular is fine for API
        cfg.allowsExpensiveNetworkAccess = true     // cellular is OK; uploads respect §20.6
        cfg.httpAdditionalHeaders = [
            "X-Origin": "ios",
            "Accept": "application/json",
            "Accept-Encoding": "gzip, br"           // §29.7 compression
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
