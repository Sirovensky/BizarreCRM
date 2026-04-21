import Foundation
@testable import Networking

/// Minimum-surface APIClient stub for Invoices view-model tests.
actor StubAPIClient: APIClient {
    private let createResult: Result<CreatedResource, Error>?
    private let postResults: [String: Result<Data, Error>]

    init(
        createResult: Result<CreatedResource, Error>? = nil,
        postResults: [String: Result<Data, Error>] = [:]
    ) {
        self.createResult = createResult
        self.postResults = postResults
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Check per-path results first
        for (suffix, result) in postResults {
            if path.hasSuffix(suffix) {
                switch result {
                case .success(let data):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    return try decoder.decode(T.self, from: data)
                case .failure(let err):
                    throw err
                }
            }
        }
        // Fall back to createResult for invoice creation
        guard path.hasPrefix("/api/v1/invoices"), let result = createResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let created):
            guard let cast = created as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Helpers

extension StubAPIClient {
    static func paymentSuccess(id: Int64 = 1, status: String = "paid") -> StubAPIClient {
        let payload = """
        {"id":\(id),"status":"\(status)","amount_cents":5000,"balance_cents":0}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/payment": .success(payload)])
    }

    static func paymentFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/payment": .failure(error)])
    }

    static func refundSuccess(id: Int64 = 10) -> StubAPIClient {
        let payload = """
        {"id":\(id),"status":"refunded"}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/refund": .success(payload)])
    }

    static func refundFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/refund": .failure(error)])
    }

    static func voidSuccess(id: Int64 = 99) -> StubAPIClient {
        let payload = """
        {"id":\(id),"status":"void"}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/void": .success(payload)])
    }

    static func voidFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/void": .failure(error)])
    }
}
