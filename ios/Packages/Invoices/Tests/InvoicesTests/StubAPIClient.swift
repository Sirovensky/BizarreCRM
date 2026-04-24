import Foundation
@testable import Networking

/// Minimum-surface APIClient stub for Invoices view-model tests.
/// Endpoint paths after §7 fix:
///   - Payment: POST /api/v1/invoices/:id/payments  (suffix: /payments)
///   - Refund:  POST /api/v1/refunds                (suffix: /refunds)
///   - Void:    POST /api/v1/invoices/:id/void      (suffix: /void)
actor StubAPIClient: APIClient {
    private let createResult: Result<CreatedResource, Error>?
    private let postResults: [String: Result<Data, Error>]
    private let patchResults: [String: Result<Data, Error>]

    init(
        createResult: Result<CreatedResource, Error>? = nil,
        postResults: [String: Result<Data, Error>] = [:],
        patchResults: [String: Result<Data, Error>] = [:]
    ) {
        self.createResult = createResult
        self.postResults = postResults
        self.patchResults = patchResults
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Check per-path results first (longest-suffix match wins)
        let matched = postResults
            .filter { path.hasSuffix($0.key) }
            .max(by: { $0.key.count < $1.key.count })
        if let matched {
            switch matched.value {
            case .success(let data):
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            case .failure(let err):
                throw err
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
        let matched = patchResults
            .filter { path.hasSuffix($0.key) }
            .max(by: { $0.key.count < $1.key.count })
        if let matched {
            switch matched.value {
            case .success(let data):
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            case .failure(let err):
                throw err
            }
        }
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
    /// Payment success — POST /api/v1/invoices/:id/payments
    static func paymentSuccess(id: Int64 = 1, status: String = "paid") -> StubAPIClient {
        let payload = """
        {"id":\(id),"status":"\(status)","amount_paid":50.00,"amount_due":0.00}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/payments": .success(payload)])
    }

    static func paymentFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/payments": .failure(error)])
    }

    /// Refund success — POST /api/v1/refunds
    static func refundSuccess(id: Int64 = 10) -> StubAPIClient {
        let payload = """
        {"id":\(id)}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/refunds": .success(payload)])
    }

    static func refundFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/refunds": .failure(error)])
    }

    /// Void success — POST /api/v1/invoices/:id/void
    /// Server responds with { success:true, data: { message: "Invoice voided, stock restored" } }.
    /// InvoiceVoidResponse decodes { message: String? }. InvoiceVoidViewModel synthesises
    /// VoidResult.id from its own invoiceId — the stub payload only needs the message field.
    static func voidSuccess() -> StubAPIClient {
        let payload = """
        {"message":"Invoice voided, stock restored"}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/void": .success(payload)])
    }

    static func voidFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/void": .failure(error)])
    }
}
