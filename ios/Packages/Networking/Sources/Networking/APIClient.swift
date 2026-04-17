import Foundation
import Core

public protocol APIClient: Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func delete(_ path: String) async throws

    /// Raw unwrapped envelope — for endpoints where you want the message (e.g. SERVER validation).
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T>

    func setAuthToken(_ token: String?) async
    func setBaseURL(_ url: URL?) async
    func currentBaseURL() async -> URL?
}

public extension APIClient {
    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }
}

public actor APIClientImpl: APIClient {
    private var baseURL: URL?
    private var authToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(initialBaseURL: URL? = nil, pinnedSPKIBase64: Set<String> = []) {
        self.baseURL = initialBaseURL

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "X-Origin": "ios",
            "Accept": "application/json"
        ]

        if pinnedSPKIBase64.isEmpty {
            self.session = URLSession(configuration: cfg)
        } else {
            let delegate = PinnedURLSessionDelegate(pinnedSPKIBase64: pinnedSPKIBase64)
            self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func setAuthToken(_ token: String?) { self.authToken = token }
    public func setBaseURL(_ url: URL?) { self.baseURL = url }
    public func currentBaseURL() -> URL? { baseURL }

    public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "GET", query: query, body: nil as String?), as: T.self))
    }

    public func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        try await perform(request(path, method: "GET", query: query, body: nil as String?), as: T.self)
    }

    public func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await unwrap(perform(request(path, method: "POST", query: nil, body: body), as: T.self))
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
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    private func perform<T: Decodable & Sendable>(_ req: URLRequest, as _: T.Type) async throws -> APIResponse<T> {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APITransportError.invalidResponse }

        if http.statusCode == 401 { throw APITransportError.unauthorized }

        do {
            let envelope = try decoder.decode(APIResponse<T>.self, from: data)
            if !(200..<300).contains(http.statusCode) {
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

    private func unwrap<T: Decodable & Sendable>(_ envelope: APIResponse<T>) throws -> T {
        guard envelope.success, let payload = envelope.data else {
            throw APITransportError.envelopeFailure(message: envelope.message)
        }
        return payload
    }
}

private struct EmptyPayload: Decodable, Sendable {}
