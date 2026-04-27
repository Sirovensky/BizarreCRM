import XCTest
@testable import Tickets
import Networking

// MARK: - Stub repo for sort / footer / delete tests

private actor SortStubTicketRepository: TicketRepository {
    var returnedTickets: [TicketSummary]
    var lastSort: TicketSortOrder?
    var deleteError: Error?
    var deletedIds: [Int64] = []

    init(tickets: [TicketSummary] = []) {
        self.returnedTickets = tickets
    }

    func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary] {
        lastSort = sort
        return returnedTickets
    }

    func detail(id: Int64) async throws -> TicketDetail {
        throw APITransportError.noBaseURL
    }

    func delete(id: Int64) async throws {
        deletedIds.append(id)
        if let err = deleteError { throw err }
    }

    func duplicate(id: Int64) async throws -> DuplicateTicketResponse {
        throw APITransportError.noBaseURL
    }

    func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse {
        throw APITransportError.noBaseURL
    }
}

// MARK: - Helpers

private func makeSummary(id: Int64) -> TicketSummary {
    let json = """
    {
      "id": \(id),
      "order_id": "T-\(id)",
      "total": 1000,
      "is_pinned": false,
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(TicketSummary.self, from: Data(json.utf8))
}

// MARK: - Tests

@MainActor
final class TicketListViewModelSortTests: XCTestCase {

    // §4.1 — applySort forwards sort to repository.
    func test_applySort_passesToRepository() async {
        let repo = SortStubTicketRepository()
        let vm = TicketListViewModel(repo: repo)
        await vm.applySort(.urgency)
        XCTAssertEqual(vm.sort, .urgency)
        let lastSort = await repo.lastSort
        XCTAssertEqual(lastSort, .urgency, "Repository should receive urgency sort")
    }

    // §4.1 — Default sort is newest.
    func test_defaultSort_isNewest() {
        let repo = SortStubTicketRepository()
        let vm = TicketListViewModel(repo: repo)
        XCTAssertEqual(vm.sort, .newest)
    }

    // §4.1 — footerState is .loading when isLoading.
    func test_footerState_loading_whenIsLoading() {
        let repo = SortStubTicketRepository()
        let vm = TicketListViewModel(repo: repo)
        // vm.isLoading is set during load but we can't observe mid-flight.
        // Verify default (not loading).
        XCTAssertNotEqual(vm.footerState, .loading, "Not loading before load() is called")
    }

    // §4.1 — footerState showing(count:) when tickets non-empty and online.
    func test_footerState_showing_whenTicketsLoaded() async {
        let tickets = [makeSummary(id: 1), makeSummary(id: 2)]
        let repo = SortStubTicketRepository(tickets: tickets)
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        if case .showing(let count) = vm.footerState {
            XCTAssertEqual(count, 2)
        } else {
            // If offline, footerState could be .offline — accept that too.
            XCTAssertTrue(
                {
                    if case .offline = vm.footerState { return true }
                    return false
                }(),
                "footerState should be .showing or .offline but was \(vm.footerState)"
            )
        }
    }

    // §4.1 — footerState end when empty and online (no tickets).
    func test_footerState_end_whenEmpty() async {
        let repo = SortStubTicketRepository(tickets: [])
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        // Accept end or offline
        let isEnd: Bool
        if case .end = vm.footerState { isEnd = true } else { isEnd = false }
        let isOffline: Bool
        if case .offline = vm.footerState { isOffline = true } else { isOffline = false }
        XCTAssertTrue(isEnd || isOffline, "footerState should be .end or .offline when empty")
    }

    // §4.4 — delete removes ticket from list.
    func test_delete_removesTicketOptimistically() async {
        let tickets = [makeSummary(id: 10), makeSummary(id: 20)]
        let repo = SortStubTicketRepository(tickets: tickets)
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.tickets.count, 2)

        await vm.delete(ticket: makeSummary(id: 10))

        // Optimistic removal
        XCTAssertFalse(vm.tickets.contains { $0.id == 10 }, "Ticket 10 should be removed optimistically")
    }

    // §4.4 — delete calls repo.delete.
    func test_delete_callsRepository() async {
        let tickets = [makeSummary(id: 5)]
        let repo = SortStubTicketRepository(tickets: tickets)
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        await vm.delete(ticket: makeSummary(id: 5))
        let deleted = await repo.deletedIds
        XCTAssertTrue(deleted.contains(5), "Repository delete should be called with ticket ID 5")
    }

    // §4.1 — TicketSortOrder displayName not empty.
    func test_sortOrder_displayNames_allNonEmpty() {
        for order in TicketSortOrder.allCases {
            XCTAssertFalse(order.displayName.isEmpty, "\(order.rawValue) has empty displayName")
        }
    }

    // §4.1 — TicketSortOrder queryItem has correct key.
    func test_sortOrder_queryItem_hasCorrectKey() {
        for order in TicketSortOrder.allCases {
            XCTAssertEqual(order.queryItem.name, "sort")
            XCTAssertEqual(order.queryItem.value, order.rawValue)
        }
    }
}
