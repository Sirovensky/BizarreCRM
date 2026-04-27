import Foundation
import Observation
import Core
import Networking

// MARK: - §4.1 Cursor-based pagination + GRDB cache controller
//
// Manages the cursor state for the ticket list:
//   - First fetch: cursor = nil → first page.
//   - Subsequent fetches: cursor = lastCursor → next page.
//   - `serverExhaustedAt`: set when the server returns nextCursor = nil, so
//     we know we've loaded all rows for this filter combination.
//   - `hasMore`: derived from whether serverExhaustedAt is nil (not from total_pages).
//
// The controller is filter-scoped: changing the filter resets cursor state.

@MainActor
@Observable
public final class TicketCursorPaginationController {

    // MARK: - Paged state (per filter+keyword+sort key)

    private struct PageState {
        var nextCursor: String?
        var serverExhaustedAt: Date?
        var oldestCachedAt: Date?

        var hasMore: Bool { serverExhaustedAt == nil }
    }

    // MARK: - Published state

    public private(set) var isFetchingNextPage: Bool = false
    public private(set) var lastError: String?

    // MARK: - Internal state

    private var pageStates: [String: PageState] = [:]
    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Returns true if there are more pages available for the given key.
    public func hasMore(for key: String) -> Bool {
        pageStates[key]?.hasMore ?? true
    }

    /// Returns the next cursor for the given key (nil = first page).
    public func nextCursor(for key: String) -> String? {
        pageStates[key]?.nextCursor
    }

    /// Called when the list scroll reaches the last visible row —
    /// triggers a background fetch of the next page via cursor.
    ///
    /// - Returns: Fetched tickets to upsert into GRDB (or empty when exhausted).
    @discardableResult
    public func loadNextPage(
        filter: TicketListFilter,
        keyword: String?,
        sort: TicketSortOrder
    ) async throws -> [TicketSummary] {
        let key = pageKey(filter: filter, keyword: keyword, sort: sort)

        // Guard: do not fetch if already loading or server exhausted.
        guard !isFetchingNextPage else { return [] }
        let state = pageStates[key]
        guard state?.serverExhaustedAt == nil else { return [] }

        isFetchingNextPage = true
        lastError = nil
        defer { isFetchingNextPage = false }

        let page = try await api.listTicketsCursor(
            filter: filter,
            keyword: keyword,
            sort: sort,
            cursor: state?.nextCursor,
            limit: 50
        )

        let now = Date()
        var updated = state ?? PageState()
        updated.nextCursor = page.nextCursor
        updated.oldestCachedAt = updated.oldestCachedAt ?? now
        if page.nextCursor == nil {
            updated.serverExhaustedAt = now
        }
        pageStates[key] = updated

        AppLog.ui.debug(
            "Cursor page fetched: filter=\(filter.rawValue, privacy: .public) " +
            "count=\(page.tickets.count) hasNext=\(page.nextCursor != nil, privacy: .public)"
        )
        return page.tickets
    }

    /// Resets cursor state for a given key (call after filter/keyword/sort change).
    public func reset(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) {
        let key = pageKey(filter: filter, keyword: keyword, sort: sort)
        pageStates.removeValue(forKey: key)
    }

    /// Resets all cursor state (call on pull-to-refresh).
    public func resetAll() {
        pageStates.removeAll()
    }

    // MARK: - Private helpers

    private func pageKey(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) -> String {
        "\(filter.rawValue)|\(keyword ?? "")|\(sort.rawValue)"
    }
}
