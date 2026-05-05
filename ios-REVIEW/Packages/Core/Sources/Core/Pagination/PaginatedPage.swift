import Foundation

/// One page of server results using the page/per_page/total_pages shape that
/// existing endpoints already return.  Feature-package repositories receive
/// this from the Networking layer (via a closure injected at call-site) and
/// hand it to `PaginatedLoader`; neither type depends on Networking directly.
///
/// Compatible with the page-based pagination envelope:
///   `{ data: [...], pagination: { page, per_page, total, total_pages } }`
/// as well as manually-constructed values from tests.
public struct PaginatedPage<Item: Sendable>: Sendable {

    // MARK: - Stored properties

    public let items: [Item]
    public let page: Int
    public let perPage: Int
    public let totalPages: Int

    // MARK: - Derived

    /// `true` when the server has at least one more page beyond this one.
    public var hasMore: Bool { page < totalPages }

    // MARK: - Init

    public init(
        items: [Item],
        page: Int,
        perPage: Int,
        totalPages: Int
    ) {
        self.items = items
        self.page = page
        self.perPage = perPage
        self.totalPages = totalPages
    }
}
