import Foundation
import Core

public protocol APIClient: Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T
    func delete(_ path: String) async throws
    func setAuthToken(_ token: String?) async
    func setBaseURL(_ url: URL) async
}

public extension APIClient {
    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }
}

public actor APIClientImpl: APIClient {
    private var baseURL: URL
    private var authToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(config: APIClientConfig) {
        self.baseURL = config.baseURL

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "X-Origin": "ios",
            "Accept": "application/json"
        ]

        let delegate = PinnedURLSessionDelegate(pinnedSPKIBase64: config.pinnedSPKIBase64)
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)

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
    public func setBaseURL(_ url: URL) { self.baseURL = url }

    public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query
        guard let url = comps?.url else { throw APITransportError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        attachAuth(&req)
        return try await perform(req, as: type)
    }

    public func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        attachAuth(&req)
        return try await perform(req, as: type)
    }

    public func delete(_ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        attachAuth(&req)
        _ = try await perform(req, as: EmptyPayload.self)
    }

    private func attachAuth(_ req: inout URLRequest) {
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform<T: Decodable & Sendable>(_ req: URLRequest, as _: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APITransportError.invalidResponse }

        if http.statusCode == 401 { throw APITransportError.unauthorized }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APITransportError.httpStatus(http.statusCode, body: body)
        }

        do {
            let envelope = try decoder.decode(APIResponse<T>.self, from: data)
            guard envelope.success, let payload = envelope.data else {
                throw APITransportError.envelopeFailure(envelope.error)
            }
            return payload
        } catch let decodingError as DecodingError {
            throw APITransportError.decoding("\(decodingError)")
        }
    }
}

public struct APIClientConfig: Sendable {
    public let baseURL: URL
    public let pinnedSPKIBase64: Set<String>

    public init(baseURL: URL, pinnedSPKIBase64: Set<String>) {
        self.baseURL = baseURL
        self.pinnedSPKIBase64 = pinnedSPKIBase64
    }

    public static func fromBundle() -> APIClientConfig {
        let info = Bundle.main.infoDictionary
        let rawURL = (info?["BZ_API_BASE_URL"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://localhost:3000")!
        let pinsString = (info?["BZ_SPKI_PINS"] as? String) ?? ""
        let pins = pinsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return APIClientConfig(baseURL: rawURL, pinnedSPKIBase64: Set(pins))
    }
}

private struct EmptyPayload: Decodable, Sendable {}
