import XCTest
#if os(iOS)
@testable import Core

// MARK: - Mock implementations

final class MockCustomerIntentResolver: CustomerIntentResolver, @unchecked Sendable {
    var resolveCallCount = 0
    var suggestCallCount = 0
    var stubbedCustomer: CustomerEntity?
    var stubbedSuggestions: [CustomerEntity] = []

    func resolveCustomer(for input: String) async throws -> CustomerEntity? {
        resolveCallCount += 1
        return stubbedCustomer
    }

    func suggestCustomers(matching query: String) async throws -> [CustomerEntity] {
        suggestCallCount += 1
        return stubbedSuggestions
    }
}

final class MockTicketIntentResolver: TicketIntentResolver, @unchecked Sendable {
    var resolveCallCount = 0
    var suggestCallCount = 0
    var stubbedTicket: TicketEntity?
    var stubbedSuggestions: [TicketEntity] = []

    func resolveTicket(forOrderId orderId: String) async throws -> TicketEntity? {
        resolveCallCount += 1
        return stubbedTicket
    }

    func suggestTickets() async throws -> [TicketEntity] {
        suggestCallCount += 1
        return stubbedSuggestions
    }
}

// MARK: - CustomerIntentResolver tests

final class CustomerIntentResolverTests: XCTestCase {

    private var mock: MockCustomerIntentResolver!

    override func setUp() {
        super.setUp()
        mock = MockCustomerIntentResolver()
        CustomerIntentResolverConfig.register(mock)
    }

    func test_register_replacesDefaultNoOp() async throws {
        let resolved = try await CustomerIntentResolverRegistry.resolver.resolveCustomer(for: "Alice")
        XCTAssertEqual(mock.resolveCallCount, 1)
        XCTAssertNil(resolved)
    }

    func test_resolveCustomer_returnsStubbed() async throws {
        let expected = CustomerEntity(id: 10, displayName: "Alice", phone: "555-0001")
        mock.stubbedCustomer = expected

        let result = try await CustomerIntentResolverRegistry.resolver.resolveCustomer(for: "Alice")
        XCTAssertEqual(result?.numericId, 10)
        XCTAssertEqual(result?.displayName, "Alice")
        XCTAssertEqual(mock.resolveCallCount, 1)
    }

    func test_resolveCustomer_whenNoneFound_returnsNil() async throws {
        mock.stubbedCustomer = nil
        let result = try await CustomerIntentResolverRegistry.resolver.resolveCustomer(for: "Unknown")
        XCTAssertNil(result)
    }

    func test_suggestCustomers_returnsAllSuggestions() async throws {
        mock.stubbedSuggestions = [
            CustomerEntity(id: 1, displayName: "Bob"),
            CustomerEntity(id: 2, displayName: "Carol")
        ]

        let results = try await CustomerIntentResolverRegistry.resolver.suggestCustomers(matching: "")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(mock.suggestCallCount, 1)
    }

    func test_suggestCustomers_emptyQuery_returnsAll() async throws {
        mock.stubbedSuggestions = [CustomerEntity(id: 3, displayName: "Dave")]
        let results = try await CustomerIntentResolverRegistry.resolver.suggestCustomers(matching: "")
        XCTAssertEqual(results.count, 1)
    }

    func test_suggestCustomers_noMatch_returnsEmpty() async throws {
        mock.stubbedSuggestions = []
        let results = try await CustomerIntentResolverRegistry.resolver.suggestCustomers(matching: "xyz")
        XCTAssertTrue(results.isEmpty)
    }

    func test_noOpResolver_resolveCustomer_returnsNil() async throws {
        // Re-register a fresh no-op by bypassing the config — verify the config
        // entry-point doesn't crash when replacing again.
        let newMock = MockCustomerIntentResolver()
        CustomerIntentResolverConfig.register(newMock)
        let result = try await CustomerIntentResolverRegistry.resolver.resolveCustomer(for: "Test")
        XCTAssertNil(result)
        XCTAssertEqual(newMock.resolveCallCount, 1)
    }
}

// MARK: - TicketIntentResolver tests

final class TicketIntentResolverTests: XCTestCase {

    private var mock: MockTicketIntentResolver!

    override func setUp() {
        super.setUp()
        mock = MockTicketIntentResolver()
        TicketIntentResolverConfig.register(mock)
    }

    func test_register_replacesDefaultNoOp() async throws {
        _ = try await TicketIntentResolverRegistry.resolver.resolveTicket(forOrderId: "T-001")
        XCTAssertEqual(mock.resolveCallCount, 1)
    }

    func test_resolveTicket_returnsStubbed() async throws {
        let expected = TicketEntity(id: 42, displayId: "T-042", customerName: "Eve", status: "Ready")
        mock.stubbedTicket = expected

        let result = try await TicketIntentResolverRegistry.resolver.resolveTicket(forOrderId: "T-042")
        XCTAssertEqual(result?.numericId, 42)
        XCTAssertEqual(result?.displayId, "T-042")
        XCTAssertEqual(mock.resolveCallCount, 1)
    }

    func test_resolveTicket_unknownId_returnsNil() async throws {
        mock.stubbedTicket = nil
        let result = try await TicketIntentResolverRegistry.resolver.resolveTicket(forOrderId: "T-999")
        XCTAssertNil(result)
    }

    func test_suggestTickets_returnsAllSuggestions() async throws {
        mock.stubbedSuggestions = [
            TicketEntity(id: 1, displayId: "T-001", customerName: "Frank", status: "Intake"),
            TicketEntity(id: 2, displayId: "T-002", customerName: "Grace", status: "Ready")
        ]

        let results = try await TicketIntentResolverRegistry.resolver.suggestTickets()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(mock.suggestCallCount, 1)
    }

    func test_suggestTickets_empty_returnsEmpty() async throws {
        mock.stubbedSuggestions = []
        let results = try await TicketIntentResolverRegistry.resolver.suggestTickets()
        XCTAssertTrue(results.isEmpty)
    }

    func test_noOpResolver_suggestTickets_returnsEmpty() async throws {
        let newMock = MockTicketIntentResolver()
        TicketIntentResolverConfig.register(newMock)
        let results = try await TicketIntentResolverRegistry.resolver.suggestTickets()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(newMock.suggestCallCount, 1)
    }
}
#endif // os(iOS)
