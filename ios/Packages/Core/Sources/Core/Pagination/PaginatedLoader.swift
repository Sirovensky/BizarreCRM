import Foundation
import Observation

/// @Observable actor-backed loader for paginated lists.
///
/// Ownership model — **§20 Core only**. Feature packages inject a `fetch`
/// closure rather than importing Networking; this keeps Core free of a
/// Networking dependency.
///
/// ## Typical usage (feature-package ViewModel)
/// ```swift
/// let loader = PaginatedLoader<Ticket>(fetch: { page, perPage in
///     let response = try await apiClient.get(
///         "/tickets",
///         query: [.init(name: "page", value: "\(page)"),
///                 .init(name: "per_page", value: "\(perPage)")],
///         as: TicketListEnvelope.self
///     )
///     return PaginatedPage(
///         items: response.tickets,
///         page: response.pagination.page,
///         perPage: response.pagination.perPage,
///         totalPages: response.pagination.totalPages
///     )
/// })
/// ```
///
/// SwiftUI consumes the published state directly:
/// ```swift
/// PaginatedList(loader: loader) { ticket in
///     TicketRow(ticket: ticket)
/// }
/// ```
///
/// ## Swift 6 / Sendable notes
/// The class is marked `@MainActor` so SwiftUI can bind to it without hopping
/// actors. The `fetch` closure carries `@Sendable` so callers are forced to
/// capture only sendable values. `Item` is constrained to `Identifiable &
/// Sendable` so dedup by `id` is safe from any actor.
@MainActor
@Observable
public final class PaginatedLoader<Item: Identifiable & Sendable>: Sendable {

    // MARK: - Published state

    /// All loaded items, deduped by `id`.  Ordered: first page first.
    public private(set) var items: [Item] = []

    /// `true` while a page request is in-flight.
    public private(set) var isLoadingMore: Bool = false

    /// `false` once the last page has been received or an error occurred that
    /// was not recoverable.  Flip happens immediately on receiving a page whose
    /// `hasMore == false`.
    public private(set) var hasMore: Bool = true

    /// The page that was *last successfully loaded*.  Starts at 0 (nothing
    /// loaded yet).
    public private(set) var currentPage: Int = 0

    /// Non-nil after a fetch error; cleared on the next successful fetch.
    public private(set) var error: Error?

    // MARK: - Config

    public let perPage: Int

    // MARK: - Private

    private let fetch: @Sendable (Int, Int) async throws -> PaginatedPage<Item>

    /// Tracks already-seen IDs to prevent duplicates across page loads.
    private var seenIDs: Set<Item.ID> = []

    // MARK: - Init

    /// - Parameters:
    ///   - perPage: Number of items per page.  Defaults to 50 per §20.5.
    ///   - fetch: Closure called with `(page: Int, perPage: Int)` that returns a
    ///     `PaginatedPage`.  Must be `@Sendable`; capture only `Sendable` values.
    public init(
        perPage: Int = 50,
        fetch: @Sendable @escaping (Int, Int) async throws -> PaginatedPage<Item>
    ) {
        self.perPage = perPage
        self.fetch = fetch
    }

    // MARK: - Public API

    /// Load the first page.  Resets all state.  Safe to call multiple times
    /// (idempotent while a load is in flight — a second call while loading is
    /// silently dropped).
    public func loadFirstPage() async {
        guard !isLoadingMore else { return }
        reset()
        await load(page: 1)
    }

    /// Convenience alias — same as `loadFirstPage()` but semantically clearer
    /// for pull-to-refresh.
    public func refresh() async {
        await loadFirstPage()
    }

    /// Called from `.onAppear` on each list row.  Fires the next page load when
    /// `currentItem` is close to the end of the visible data.
    ///
    /// - Parameter currentItem: The item whose row just appeared on screen.
    public func loadMoreIfNeeded(currentItem: Item) async {
        guard hasMore, !isLoadingMore, !items.isEmpty else { return }
        guard shouldTriggerLoad(for: currentItem) else { return }
        await load(page: currentPage + 1)
    }

    // MARK: - Private helpers

    private func reset() {
        items = []
        seenIDs = []
        currentPage = 0
        hasMore = true
        error = nil
    }

    private func load(page: Int) async {
        isLoadingMore = true
        error = nil
        defer { isLoadingMore = false }

        do {
            let result = try await fetch(page, perPage)
            append(newItems: result.items)
            currentPage = result.page
            hasMore = result.hasMore
        } catch {
            self.error = error
            // Don't flip hasMore on error so the caller can retry.
        }
    }

    /// Append items that haven't been seen before (dedup by `id`).
    private func append(newItems: [Item]) {
        let unique = newItems.filter { seenIDs.insert($0.id).inserted }
        items += unique
    }

    /// Trigger threshold: fire when `currentItem` is within the last 10 items.
    private func shouldTriggerLoad(for item: Item) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return false
        }
        let threshold = max(0, items.count - 10)
        return index >= threshold
    }
}
