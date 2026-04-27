import Foundation
import Networking

// MARK: - EstimateRepository

/// Repository protocol for the Estimates read surface.
/// The existing `EstimateListViewModel` called `APIClient` directly;
/// this protocol abstracts the data layer for testability and caching.
public protocol EstimateRepository: Sendable {
    func list(keyword: String?) async throws -> [Estimate]
    /// §8.1 — filter by status tab + cursor pagination.
    func listPage(
        status: EstimateStatusFilter,
        keyword: String?,
        cursor: String?
    ) async throws -> EstimatePageResult
}

// MARK: - EstimatePageResult

/// One page of estimates with cursor forwarding.
public struct EstimatePageResult: Sendable {
    public let estimates: [Estimate]
    public let nextCursor: String?

    public init(estimates: [Estimate], nextCursor: String?) {
        self.estimates = estimates
        self.nextCursor = nextCursor
    }
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

    public func listPage(
        status: EstimateStatusFilter,
        keyword: String?,
        cursor: String?
    ) async throws -> EstimatePageResult {
        let resp = try await api.listEstimatesCursor(
            status: status,
            keyword: keyword,
            cursor: cursor
        )
        return EstimatePageResult(estimates: resp.estimates, nextCursor: resp.nextCursor)
    }
}
