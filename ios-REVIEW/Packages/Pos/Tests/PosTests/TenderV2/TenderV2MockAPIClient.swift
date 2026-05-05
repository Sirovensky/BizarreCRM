#if canImport(UIKit)
import Foundation
import Networking

// MARK: - MockError

struct TenderV2MockError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let generic = TenderV2MockError(message: "Mock API error")
    static let network = TenderV2MockError(message: "Network unavailable")
}

// MARK: - TenderV2MockAPIClient

/// Minimal `APIClient` stub for PosTenderCoordinator tests.
///
/// Configure `transactionResult` to control `POST /pos/transaction` outcomes.
final class TenderV2MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Configuration

    /// Result returned by `POST /api/v1/pos/transaction`.
    var transactionResult: Result<PosTransactionResponse, Error> = .success(
        PosTransactionResponse(
            invoice: PosTransactionInvoice(id: 101, orderId: "INV-001", totalCents: 10000),
            message: nil
        )
    )

    /// Captures the last request body posted to `/pos/transaction`.
    var lastTransactionRequest: PosTransactionRequest?

    /// Counter for how many times `/pos/transaction` was called.
    var transactionCallCount: Int = 0

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        if path == "/api/v1/pos/transaction" {
            transactionCallCount += 1
            if let req = body as? PosTransactionRequest {
                lastTransactionRequest = req
            }
            let response = try transactionResult.get()
            guard let typed = response as? T else { throw TenderV2MockError.generic }
            return typed
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        throw URLError(.badURL)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        throw URLError(.badURL)
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> APIResponse<T> {
        throw URLError(.badURL)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
