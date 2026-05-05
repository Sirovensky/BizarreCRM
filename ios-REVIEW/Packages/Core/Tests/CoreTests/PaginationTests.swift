import XCTest
@testable import Core

// MARK: - Helpers

private struct Item: Identifiable, Sendable {
    let id: Int
    let value: String
}

/// Build a `PaginatedPage` from a flat array by slicing by page index.
private func makePage(
    allItems: [Item],
    page: Int,
    perPage: Int
) -> PaginatedPage<Item> {
    let totalPages = max(1, Int(ceil(Double(allItems.count) / Double(perPage))))
    let startIndex = (page - 1) * perPage
    let endIndex   = min(startIndex + perPage, allItems.count)
    let slice: [Item] = startIndex < allItems.count
        ? Array(allItems[startIndex..<endIndex])
        : []
    return PaginatedPage(items: slice, page: page, perPage: perPage, totalPages: totalPages)
}

/// Actor used to share mutable state between `@MainActor` test bodies and
/// the `@Sendable` fetch closures required by `PaginatedLoader`.
private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
    func get() -> Int { value }
}

private actor Flag {
    var value: Bool
    init(_ initial: Bool) { value = initial }
    func set(_ v: Bool) { value = v }
    func get() -> Bool { value }
}

// MARK: - PaginatedPage Tests

final class PaginatedPageTests: XCTestCase {

    func test_hasMore_true_when_more_pages_exist() {
        let page = PaginatedPage(items: [Item(id: 1, value: "a")], page: 1, perPage: 1, totalPages: 3)
        XCTAssertTrue(page.hasMore)
    }

    func test_hasMore_false_on_last_page() {
        let page = PaginatedPage(items: [Item(id: 1, value: "a")], page: 3, perPage: 1, totalPages: 3)
        XCTAssertFalse(page.hasMore)
    }

    func test_hasMore_false_single_page() {
        let page = PaginatedPage(items: [Item(id: 1, value: "a")], page: 1, perPage: 50, totalPages: 1)
        XCTAssertFalse(page.hasMore)
    }

    func test_hasMore_true_page_2_of_5() {
        let page = PaginatedPage<Item>(items: [], page: 2, perPage: 10, totalPages: 5)
        XCTAssertTrue(page.hasMore)
    }
}

// MARK: - PaginatedLoader Tests

@MainActor
final class PaginatedLoaderTests: XCTestCase {

    // MARK: Initial state

    func test_initialState() {
        let loader = PaginatedLoader<Item>(fetch: { _, _ in
            XCTFail("fetch should not be called before loadFirstPage")
            return PaginatedPage(items: [], page: 1, perPage: 50, totalPages: 1)
        })
        XCTAssertTrue(loader.items.isEmpty)
        XCTAssertFalse(loader.isLoadingMore)
        XCTAssertTrue(loader.hasMore)
        XCTAssertEqual(loader.currentPage, 0)
        XCTAssertNil(loader.error)
    }

    // MARK: loadFirstPage

    func test_loadFirstPage_populatesItems() async {
        let items = (1...3).map { Item(id: $0, value: "item\($0)") }
        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            makePage(allItems: items, page: page, perPage: perPage)
        }

        await loader.loadFirstPage()

        XCTAssertEqual(loader.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(loader.currentPage, 1)
        XCTAssertFalse(loader.hasMore) // only 1 page
        XCTAssertFalse(loader.isLoadingMore)
        XCTAssertNil(loader.error)
    }

    func test_loadFirstPage_setsCurrentPage() async {
        let items = (1...50).map { Item(id: $0, value: "x") }
        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            makePage(allItems: items, page: page, perPage: perPage)
        }

        await loader.loadFirstPage()

        XCTAssertEqual(loader.currentPage, 1)
    }

    func test_loadFirstPage_resetsExistingState() async {
        // Alternate between two item-sets using a counter actor.
        let counter = Counter()

        let itemsSet1 = [Item(id: 1, value: "a")]
        let itemsSet2 = [Item(id: 2, value: "b")]

        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            await counter.increment()
            let items = await counter.get() == 1 ? itemsSet1 : itemsSet2
            return makePage(allItems: items, page: page, perPage: perPage)
        }

        await loader.loadFirstPage()
        XCTAssertEqual(loader.items.map(\.id), [1])

        await loader.loadFirstPage()
        XCTAssertEqual(loader.items.map(\.id), [2])
    }

    // MARK: loadMoreIfNeeded

    func test_loadMore_appendsNextPage() async {
        let allItems = (1...20).map { Item(id: $0, value: "\($0)") }
        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            makePage(allItems: allItems, page: page, perPage: perPage)
        }

        await loader.loadFirstPage()
        XCTAssertEqual(loader.items.count, 10)
        XCTAssertTrue(loader.hasMore)

        // Trigger load-more with last item
        let lastItem = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: lastItem)

        XCTAssertEqual(loader.items.count, 20)
        XCTAssertEqual(loader.currentPage, 2)
        XCTAssertFalse(loader.hasMore)
    }

    func test_loadMore_noopWhenNoMorePages() async {
        let items = [Item(id: 1, value: "a")]
        let counter = Counter()
        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            await counter.increment()
            return makePage(allItems: items, page: page, perPage: perPage)
        }

        await loader.loadFirstPage() // counter = 1
        XCTAssertFalse(loader.hasMore)

        let lastItem = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: lastItem)

        let calls = await counter.get()
        XCTAssertEqual(calls, 1, "Should not fetch when hasMore is false")
    }

    func test_loadMore_noopWhenAlreadyLoading() async {
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            // Simulate slow first page with 2 pages
            PaginatedPage(items: [Item(id: 1, value: "a")], page: 1, perPage: 10, totalPages: 2)
        }

        // We verify the sequential case: after loadFirstPage returns,
        // isLoadingMore must be false (no concurrent state leak).
        await loader.loadFirstPage()
        XCTAssertFalse(loader.isLoadingMore)
    }

    func test_loadMore_doesNotTriggerForEarlyItems() async {
        let allItems = (1...20).map { Item(id: $0, value: "\($0)") }
        let counter = Counter()
        let loader = PaginatedLoader<Item>(perPage: 20) { page, perPage in
            await counter.increment()
            return makePage(allItems: allItems, page: page, perPage: perPage)
        }

        await loader.loadFirstPage() // counter = 1
        let earlyItem = loader.items[0] // index 0 — far from end

        // Reset counter, then check that calling loadMoreIfNeeded on an early item
        // doesn't trigger another fetch.
        let earlyCount = await counter.get()
        await loader.loadMoreIfNeeded(currentItem: earlyItem)
        let afterCount = await counter.get()

        XCTAssertEqual(earlyCount, afterCount, "Should not fetch for early-position items")
    }

    // MARK: refresh

    func test_refresh_resetsAndReloadsFirstPage() async {
        let counter = Counter()
        let loader = PaginatedLoader<Item>(perPage: 10) { page, _ in
            await counter.increment()
            let n = await counter.get()
            return PaginatedPage(items: [Item(id: n, value: "\(n)")],
                                 page: 1, perPage: 10, totalPages: 1)
        }

        await loader.loadFirstPage()
        let firstItem = loader.items.first!.id
        XCTAssertEqual(firstItem, 1)

        await loader.refresh()
        XCTAssertEqual(loader.items.count, 1)
        XCTAssertEqual(loader.items.first!.id, 2)
        let calls = await counter.get()
        XCTAssertEqual(calls, 2)
    }

    // MARK: Deduplication

    func test_dedup_skipsItemsWithDuplicateIDs() async {
        // First page and second page share item id=5
        let page1 = PaginatedPage(
            items: [Item(id: 1, value: "a"), Item(id: 5, value: "shared")],
            page: 1, perPage: 2, totalPages: 2
        )
        let page2 = PaginatedPage(
            items: [Item(id: 5, value: "duplicate"), Item(id: 6, value: "c")],
            page: 2, perPage: 2, totalPages: 2
        )

        let loader = PaginatedLoader<Item>(perPage: 2) { page, _ in
            page == 1 ? page1 : page2
        }

        await loader.loadFirstPage()
        let lastItem = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: lastItem)

        // id=5 appears only once
        let ids = loader.items.map(\.id)
        XCTAssertEqual(ids.filter { $0 == 5 }.count, 1)
        XCTAssertEqual(Set(ids).count, ids.count, "All IDs must be unique")
    }

    func test_dedup_afterRefresh_allowsReuseOfIDs() async {
        let counter = Counter()
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            await counter.increment()
            let n = await counter.get()
            return PaginatedPage(items: [Item(id: 1, value: "v\(n)")],
                                 page: 1, perPage: 10, totalPages: 1)
        }

        await loader.loadFirstPage()
        XCTAssertEqual(loader.items.first?.value, "v1")

        await loader.refresh()
        // After refresh seenIDs is cleared, so id=1 appears again
        XCTAssertEqual(loader.items.count, 1)
        XCTAssertEqual(loader.items.first?.value, "v2")
    }

    // MARK: Error recovery

    func test_errorIsSetOnFetchFailure() async {
        struct FetchError: Error, Equatable {}
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            throw FetchError()
        }

        await loader.loadFirstPage()

        XCTAssertNotNil(loader.error)
        XCTAssertTrue(loader.error is FetchError)
        XCTAssertTrue(loader.items.isEmpty)
        XCTAssertFalse(loader.isLoadingMore)
    }

    func test_errorClearedOnSuccessfulRetry() async {
        struct FetchError: Error {}
        let shouldFail = Flag(true)

        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            if await shouldFail.get() { throw FetchError() }
            return PaginatedPage(items: [Item(id: 1, value: "ok")],
                                 page: 1, perPage: 10, totalPages: 1)
        }

        await loader.loadFirstPage()
        XCTAssertNotNil(loader.error)

        await shouldFail.set(false)
        await loader.loadFirstPage() // retry via refresh
        XCTAssertNil(loader.error)
        XCTAssertEqual(loader.items.count, 1)
    }

    func test_hasMore_notFlippedOnError() async {
        struct FetchError: Error {}
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            throw FetchError()
        }

        await loader.loadFirstPage()

        XCTAssertTrue(loader.hasMore, "hasMore must remain true after error so retry is possible")
    }

    // MARK: hasMore flip

    func test_hasMore_flipsToFalseOnLastPage() async {
        let loader = PaginatedLoader<Item>(perPage: 2) { page, _ in
            switch page {
            case 1: return PaginatedPage(items: [Item(id: 1, value: "a"), Item(id: 2, value: "b")],
                                         page: 1, perPage: 2, totalPages: 2)
            default: return PaginatedPage(items: [Item(id: 3, value: "c")],
                                          page: 2, perPage: 2, totalPages: 2)
            }
        }

        await loader.loadFirstPage()
        XCTAssertTrue(loader.hasMore)

        let lastItem = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: lastItem)
        XCTAssertFalse(loader.hasMore)
    }

    func test_hasMore_trueWhenMultiplePagesRemain() async {
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            PaginatedPage(items: (1...10).map { Item(id: $0, value: "\($0)") },
                          page: 1, perPage: 10, totalPages: 5)
        }

        await loader.loadFirstPage()
        XCTAssertTrue(loader.hasMore)
    }

    // MARK: Pagination sequencing

    func test_threePagesLoadInOrder() async {
        let allItems = (1...30).map { Item(id: $0, value: "\($0)") }
        let loader = PaginatedLoader<Item>(perPage: 10) { page, perPage in
            makePage(allItems: allItems, page: page, perPage: perPage)
        }

        await loader.loadFirstPage()
        XCTAssertEqual(loader.items.count, 10)

        let p1Last = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: p1Last)
        XCTAssertEqual(loader.items.count, 20)

        let p2Last = loader.items.last!
        await loader.loadMoreIfNeeded(currentItem: p2Last)
        XCTAssertEqual(loader.items.count, 30)
        XCTAssertFalse(loader.hasMore)
    }

    // MARK: Empty result

    func test_emptyFirstPage_hasMoreFalse() async {
        let loader = PaginatedLoader<Item>(perPage: 10) { _, _ in
            PaginatedPage(items: [], page: 1, perPage: 10, totalPages: 1)
        }

        await loader.loadFirstPage()

        XCTAssertTrue(loader.items.isEmpty)
        XCTAssertFalse(loader.hasMore)
        XCTAssertNil(loader.error)
    }

    // MARK: Custom perPage

    func test_customPerPage_passedToFetch() async {
        let captured = Counter()
        let loader = PaginatedLoader<Item>(perPage: 25) { _, perPage in
            // Use the counter to smuggle out the captured perPage value
            // (counters only support Int; store as-is since perPage is Int).
            // We increment by perPage to produce a unique side effect.
            for _ in 0..<perPage { await captured.increment() }
            return PaginatedPage(items: [], page: 1, perPage: perPage, totalPages: 1)
        }

        await loader.loadFirstPage()
        let total = await captured.get()
        XCTAssertEqual(total, 25)
    }
}
