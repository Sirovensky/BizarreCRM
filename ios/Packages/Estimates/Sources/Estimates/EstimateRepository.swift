import Foundation
import Networking

// MARK: - EstimateRepository

/// Repository protocol for the Estimates read surface.
/// The existing `EstimateListViewModel` called `APIClient` directly;
/// this protocol abstracts the data layer for testability and caching.
public protocol EstimateRepository: Sendable {
    func list(keyword: String?) async throws -> [Estimate]

    // §8.1: Cursor-based pagination (offline-first).
    // Fetches one page via `GET /estimates?cursor=<opaque>&limit=50`.
    // When `cursor` is nil the first page is returned.
    // Callers check `EstimatesCursorPage.hasMore` and advance with `nextCursor`.
    func listPage(cursor: String?, keyword: String?, status: String?) async throws -> EstimatesCursorPage
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

    // §8.1: Cursor-based pagination via the dedicated cursor endpoint.
    // Graceful fallback: if the server does not yet support cursor pagination
    // (returns a non-cursor shape), the error propagates and the caller
    // can fall back to the non-cursor `list(keyword:)` path.
    public func listPage(cursor: String?, keyword: String?, status: String?) async throws -> EstimatesCursorPage {
        try await api.listEstimatesCursor(cursor: cursor, keyword: keyword, status: status)
    }
}
