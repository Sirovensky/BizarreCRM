import Foundation
import Networking

// MARK: - EstimateRepository

/// Repository protocol for the Estimates read surface.
/// The existing `EstimateListViewModel` called `APIClient` directly;
/// this protocol abstracts the data layer for testability and caching.
public protocol EstimateRepository: Sendable {
    func list(keyword: String?) async throws -> [Estimate]
}

// MARK: - EstimateRepositoryImpl

/// Direct-to-API implementation (no caching). Kept intact so existing
/// call sites remain unmodified. Use `EstimateCachedRepositoryImpl` for
/// the Phase 3 read surface.
public actor EstimateRepositoryImpl: EstimateRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(keyword: String?) async throws -> [Estimate] {
        try await api.listEstimates(keyword: keyword)
    }
}
