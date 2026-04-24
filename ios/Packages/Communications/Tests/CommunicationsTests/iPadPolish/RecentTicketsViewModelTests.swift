import XCTest
@testable import Communications
@testable import Networking

// MARK: - RecentTicketsViewModelTests
//
// Unit tests for RecentTicketsViewModel (iPad polish §3 — Recent Tickets section).
// No UI or network I/O — all I/O is stubbed via MockTicketsAPIClient.

final class RecentTicketsViewModelTests: XCTestCase {

    // MARK: - Load success — tickets filtered and capped at 3

    @MainActor
    func test_load_success_returnsUpToThreeTickets() async {
        let tickets = makeTickets(customerIds: [1, 1, 1, 1], orderIds: ["A", "B", "C", "D"])
        let api = MockTicketsAPIClient(tickets: tickets)
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: "Alice")

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.tickets.count, RecentTicketsViewModel.maxTickets)
    }

    @MainActor
    func test_load_success_filtersToMatchingCustomerId() async {
        let tickets = makeTickets(customerIds: [1, 2, 1], orderIds: ["A", "B", "C"])
        let api = MockTicketsAPIClient(tickets: tickets)
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: nil)

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.tickets.allSatisfy { $0.customerId == 1 })
        XCTAssertEqual(vm.tickets.count, 2)
    }

    @MainActor
    func test_load_success_ticketsSortedDescByCreatedAt() async {
        let older = makeTicket(id: 10, customerId: 1, orderId: "OLD", createdAt: "2026-01-01T00:00:00Z")
        let newer = makeTicket(id: 20, customerId: 1, orderId: "NEW", createdAt: "2026-04-23T00:00:00Z")
        let api = MockTicketsAPIClient(tickets: [older, newer])
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: nil)

        XCTAssertEqual(vm.tickets.first?.orderId, "NEW")
    }

    // MARK: - Load success — empty (no tickets for customer)

    @MainActor
    func test_load_emptyResult_stateIsLoaded_ticketsEmpty() async {
        let api = MockTicketsAPIClient(tickets: [])
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 42, customerName: "Bob")

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.tickets.isEmpty)
    }

    @MainActor
    func test_load_noMatchingCustomer_ticketsEmpty() async {
        // Server returns tickets for customer 99 only; we request customer 1
        let tickets = makeTickets(customerIds: [99, 99], orderIds: ["X", "Y"])
        let api = MockTicketsAPIClient(tickets: tickets)
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: "Charlie")

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.tickets.isEmpty)
    }

    // MARK: - Load error (network / 404 / server error)

    @MainActor
    func test_load_networkError_stateIsError() async {
        let api = MockTicketsAPIClient(error: URLError(.notConnectedToInternet))
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: nil)

        if case .error = vm.state { /* pass */ } else {
            XCTFail("Expected .error but got \(vm.state)")
        }
        XCTAssertTrue(vm.tickets.isEmpty)
    }

    @MainActor
    func test_load_notFoundError_stateIsError() async {
        let api = MockTicketsAPIClient(error: APITransportError.httpStatus(404, message: nil))
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 5, customerName: nil)

        if case .error = vm.state { /* pass */ } else {
            XCTFail("Expected .error but got \(vm.state)")
        }
    }

    // MARK: - No customer (customerId == 0)

    @MainActor
    func test_load_zeroCustomerId_stateIsNoCustomer() async {
        let api = MockTicketsAPIClient(tickets: [])
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 0, customerName: nil)

        XCTAssertEqual(vm.state, .noCustomer)
        XCTAssertTrue(vm.tickets.isEmpty)
    }

    // MARK: - Deduplication: second load for same customer skips network call

    @MainActor
    func test_load_secondCallSameCustomer_doesNotRefetch() async {
        let api = MockTicketsAPIClient(tickets: makeTickets(customerIds: [7], orderIds: ["T1"]))
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 7, customerName: nil)
        let callsAfterFirst = await api.callCount

        await vm.load(customerId: 7, customerName: nil)

        let callsAfterSecond = await api.callCount
        XCTAssertEqual(callsAfterSecond, callsAfterFirst, "Should not fetch again for the same customerId")
    }

    // MARK: - Reset clears state

    @MainActor
    func test_reset_clearsTicketsAndState() async {
        let api = MockTicketsAPIClient(tickets: makeTickets(customerIds: [1], orderIds: ["R1"]))
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: nil)
        XCTAssertFalse(vm.tickets.isEmpty)

        vm.reset()

        XCTAssertTrue(vm.tickets.isEmpty)
        XCTAssertEqual(vm.state, .idle)
    }

    @MainActor
    func test_reset_allowsRefetchForSameCustomer() async {
        let api = MockTicketsAPIClient(tickets: makeTickets(customerIds: [1], orderIds: ["R1"]))
        let vm = RecentTicketsViewModel(api: api)

        await vm.load(customerId: 1, customerName: nil)
        vm.reset()
        await vm.load(customerId: 1, customerName: nil)

        XCTAssertEqual(vm.state, .loaded)
        let callCount = await api.callCount
        XCTAssertEqual(callCount, 2, "reset() should allow re-fetch")
    }

    // MARK: - maxTickets constant

    func test_maxTickets_isThree() {
        XCTAssertEqual(RecentTicketsViewModel.maxTickets, 3)
    }

    // MARK: - Initial state

    @MainActor
    func test_initialState_isIdle() {
        let api = MockTicketsAPIClient(tickets: [])
        let vm = RecentTicketsViewModel(api: api)

        XCTAssertEqual(vm.state, .idle)
        XCTAssertTrue(vm.tickets.isEmpty)
    }
}

// MARK: - Compact row constants (Task 2 assertions)

final class SmsThreadRowCompactTests: XCTestCase {
    func test_verticalPadding_isCompact() {
        XCTAssertLessThanOrEqual(SmsThreadRow.verticalPadding, 6,
            "Vertical padding should be <= 6 pt for compact density")
    }

    func test_avatarSize_isReduced() {
        XCTAssertLessThanOrEqual(SmsThreadRow.avatarSize, 36,
            "Avatar should be <= 36 pt for compact row")
    }

    func test_nameFontSize_is13pt() {
        XCTAssertEqual(SmsThreadRow.nameFontSize, 13)
    }

    func test_previewFontSize_is12pt() {
        XCTAssertEqual(SmsThreadRow.previewFontSize, 12)
    }
}

// MARK: - Icon rail constant tests

final class SmsIconRailTests: XCTestCase {
    func test_preferredWidth_isCompact() {
        XCTAssertLessThanOrEqual(SmsIconRail.preferredWidth, 80,
            "Rail should be narrow (~72 pt) to save space")
        XCTAssertGreaterThanOrEqual(SmsIconRail.preferredWidth, 60,
            "Rail must be wide enough to tap comfortably")
    }
}

// MARK: - MockTicketsAPIClient

private actor MockTicketsAPIClient: APIClient {
    private let tickets: [TicketSummary]
    private let error: Error?
    private(set) var callCount: Int = 0

    init(tickets: [TicketSummary] = [], error: Error? = nil) {
        self.tickets = tickets
        self.error = error
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasPrefix("/api/v1/tickets") {
            callCount += 1
            if let err = error { throw err }
            let response = TicketsListResponse(tickets: tickets, pagination: nil, statusCounts: nil)
            guard let cast = response as? T else { throw APITransportError.decoding("TicketsListResponse") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
}

// MARK: - Ticket fixture helpers (JSON-decoded since TicketSummary has no public init)

private func makeTicket(
    id: Int64,
    customerId: Int64,
    orderId: String,
    createdAt: String = "2026-04-23T00:00:00Z"
) -> TicketSummary {
    let json = """
    {
        "id": \(id),
        "order_id": "\(orderId)",
        "customer_id": \(customerId),
        "total": 0,
        "is_pinned": false,
        "created_at": "\(createdAt)",
        "updated_at": "\(createdAt)"
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(TicketSummary.self, from: json)
}

private func makeTickets(customerIds: [Int64], orderIds: [String]) -> [TicketSummary] {
    zip(customerIds, orderIds).enumerated().map { (index, pair) in
        makeTicket(id: Int64(index + 1), customerId: pair.0, orderId: pair.1)
    }
}
