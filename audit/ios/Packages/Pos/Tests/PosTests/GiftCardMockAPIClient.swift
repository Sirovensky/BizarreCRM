#if canImport(UIKit)
import Foundation
import Networking

// MARK: - MockAPIError

struct MockAPIError: Error, LocalizedError {
    var errorDescription: String? { "Mock API error" }
}

// MARK: - MockAPIClient

/// Shared mock `APIClient` for GiftCard*ViewModelTests.
///
/// Provides configurable result stubs for the gift-card endpoints used in
/// this test bundle. All other methods throw `URLError(.badURL)` by default
/// so any unexpected call fails the test explicitly.
final class MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Stubs

    var lookupResult: Result<GiftCard, Error>?
    /// Multiple lookup results returned in sequence (first call → first element, etc.).
    var lookupResults: [GiftCard]?
    /// If set, lookups at and after this 0-based index throw `MockAPIError`.
    var lookupFailAfterIndex: Int?
    private var lookupCallCount = 0

    var activateResult: Result<GiftCard, Error>?
    var createVirtualResult: Result<GiftCard, Error>?
    var reloadResult: Result<ReloadGiftCardResponse, Error>?
    var transferResult: Result<TransferGiftCardResponse, Error>?
    var refundResult: Result<InvoiceRefundResponse, Error>?

    /// Optional side-effect callback for reload — lets tests spy on whether
    /// `reloadGiftCard` was called.
    var onReload: (() -> Void)?

    // MARK: - Init

    init(
        lookupResult: Result<GiftCard, Error>? = nil,
        lookupResults: [GiftCard]? = nil,
        lookupFailAfterIndex: Int? = nil,
        activateResult: Result<GiftCard, Error>? = nil,
        createVirtualResult: Result<GiftCard, Error>? = nil,
        reloadResult: Result<ReloadGiftCardResponse, Error>? = nil,
        transferResult: Result<TransferGiftCardResponse, Error>? = nil,
        refundResult: Result<InvoiceRefundResponse, Error>? = nil
    ) {
        self.lookupResult = lookupResult
        self.lookupResults = lookupResults
        self.lookupFailAfterIndex = lookupFailAfterIndex
        self.activateResult = activateResult
        self.createVirtualResult = createVirtualResult
        self.reloadResult = reloadResult
        self.transferResult = transferResult
        self.refundResult = refundResult
    }

    // MARK: - APIClient protocol

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        // Route gift-card lookup by path prefix.
        if path.contains("/gift-cards/lookup/") {
            let index = lookupCallCount
            lookupCallCount += 1

            if let failIndex = lookupFailAfterIndex, index >= failIndex {
                throw MockAPIError()
            }
            if let results = lookupResults, index < results.count {
                guard let card = results[index] as? T else {
                    throw MockAPIError()
                }
                return card
            }
            guard let result = lookupResult else { throw MockAPIError() }
            return try result.get() as! T
        }
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        if path.contains("/activate"), let result = activateResult {
            return try result.get() as! T
        }
        if path == "/api/v1/gift-cards", let result = createVirtualResult {
            return try result.get() as! T
        }
        if path.contains("/reload") {
            onReload?()
            guard let result = reloadResult else { throw MockAPIError() }
            return try result.get() as! T
        }
        if path.contains("/gift-cards/transfer"), let result = transferResult {
            return try result.get() as! T
        }
        if path.contains("/refund"), let result = refundResult {
            return try result.get() as! T
        }
        if path.contains("/store-credit-policy") {
            // Return an empty EmptyResponse.
            let empty = EmptyResponse()
            guard let typed = empty as? T else { throw MockAPIError() }
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
