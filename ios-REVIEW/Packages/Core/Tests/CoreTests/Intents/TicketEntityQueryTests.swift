import XCTest
#if os(iOS)
@testable import Core

final class TicketEntityQueryTests: XCTestCase {

    // MARK: - Mock repo

    final class MockTicketRepo: TicketEntityRepository, @unchecked Sendable {
        var stubbedByQuery: [String: [TicketEntity]] = [:]
        var stubbedById: [String: TicketEntity] = [:]
        var matchingCallCount = 0
        var idsCallCount = 0

        func tickets(matching query: String) async throws -> [TicketEntity] {
            matchingCallCount += 1
            return stubbedByQuery[query] ?? []
        }

        func tickets(for stringIds: [String]) async throws -> [TicketEntity] {
            idsCallCount += 1
            return stringIds.compactMap { stubbedById[$0] }
        }
    }

    private var mock: MockTicketRepo!

    override func setUp() {
        super.setUp()
        mock = MockTicketRepo()
        TicketEntityQueryConfig.register(mock)
    }

    // MARK: - entities(for:)

    @available(iOS 16, *)
    func test_entitiesForIds_delegatesToRepo() async throws {
        let entity = TicketEntity(id: 42, displayId: "T-042", customerName: "Alice", status: "Ready")
        mock.stubbedById["42"] = entity

        let query = TicketEntityQuery()
        let results = try await query.entities(for: ["42"])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "42")
        XCTAssertEqual(results.first?.customerName, "Alice")
        XCTAssertEqual(mock.idsCallCount, 1)
    }

    @available(iOS 16, *)
    func test_entitiesForIds_unknownId_returnsEmpty() async throws {
        let query = TicketEntityQuery()
        let results = try await query.entities(for: ["999"])
        XCTAssertTrue(results.isEmpty)
    }

    @available(iOS 16, *)
    func test_entitiesForIds_multipleIds_returnsAllMatched() async throws {
        mock.stubbedById["1"] = TicketEntity(id: 1, displayId: "T-001", customerName: "Bob", status: "Intake")
        mock.stubbedById["2"] = TicketEntity(id: 2, displayId: "T-002", customerName: "Carol", status: "Ready")

        let query = TicketEntityQuery()
        let results = try await query.entities(for: ["1", "2", "99"])
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - entities(matching:)

    @available(iOS 16, *)
    func test_entitiesMatching_delegatesToRepo() async throws {
        let entity = TicketEntity(id: 5, displayId: "T-005", customerName: "Dave", status: "In Progress")
        mock.stubbedByQuery["dave"] = [entity]

        let query = TicketEntityQuery()
        let results = try await query.entities(matching: "dave")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.customerName, "Dave")
        XCTAssertEqual(mock.matchingCallCount, 1)
    }

    @available(iOS 16, *)
    func test_entitiesMatching_noMatch_returnsEmpty() async throws {
        let query = TicketEntityQuery()
        let results = try await query.entities(matching: "nobody")
        XCTAssertTrue(results.isEmpty)
    }

    @available(iOS 16, *)
    func test_suggestedEntities_callsMatchingWithEmptyString() async throws {
        let entity = TicketEntity(id: 3, displayId: "T-003", customerName: "Eve", status: "Completed")
        mock.stubbedByQuery[""] = [entity]

        let query = TicketEntityQuery()
        let results = try await query.suggestedEntities()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(mock.matchingCallCount, 1)
    }

    // MARK: - TicketEntity DisplayRepresentation

    func test_ticketEntity_displayRepresentation_includesDisplayId() {
        let entity = TicketEntity(
            id: 7,
            displayId: "T-007",
            customerName: "Frank",
            status: "Ready",
            deviceSummary: "iPhone 15"
        )
        // title should contain both displayId and customerName
        let title = String(localized: entity.displayRepresentation.title)
        XCTAssertTrue(title.contains("T-007"))
        XCTAssertTrue(title.contains("Frank"))
    }

    func test_ticketEntity_displayRepresentation_noDevice_omitsDeviceSuffix() {
        let entity = TicketEntity(id: 8, displayId: "T-008", customerName: "Grace", status: "Intake")
        let subtitle = entity.displayRepresentation.subtitle.map { String(localized: $0) }
        // subtitle should not crash or append "· nil"
        XCTAssertFalse(subtitle?.contains("nil") ?? false)
    }

    func test_ticketEntity_initFromTicket_mapsAllFields() {
        let ticket = Ticket(
            id: 99,
            displayId: "T-099",
            customerId: 1,
            customerName: "Heidi",
            status: .ready,
            deviceSummary: "Galaxy S24",
            createdAt: Date(),
            updatedAt: Date()
        )
        let entity = TicketEntity(from: ticket)
        XCTAssertEqual(entity.id, "99")
        XCTAssertEqual(entity.numericId, 99)
        XCTAssertEqual(entity.displayId, "T-099")
        XCTAssertEqual(entity.customerName, "Heidi")
        XCTAssertEqual(entity.status, "Ready")
        XCTAssertEqual(entity.deviceSummary, "Galaxy S24")
    }
}
#endif // os(iOS)
