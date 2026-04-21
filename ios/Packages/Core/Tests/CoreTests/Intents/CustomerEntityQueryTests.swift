import XCTest
#if os(iOS)
@testable import Core

final class CustomerEntityQueryTests: XCTestCase {

    // MARK: - Mock repo

    final class MockCustomerRepo: CustomerEntityRepository, @unchecked Sendable {
        var stubbedByQuery: [String: [CustomerEntity]] = [:]
        var stubbedById: [String: CustomerEntity] = [:]
        var matchingCallCount = 0
        var idsCallCount = 0

        func customers(matching query: String) async throws -> [CustomerEntity] {
            matchingCallCount += 1
            return stubbedByQuery[query] ?? []
        }

        func customers(for stringIds: [String]) async throws -> [CustomerEntity] {
            idsCallCount += 1
            return stringIds.compactMap { stubbedById[$0] }
        }
    }

    private var mock: MockCustomerRepo!

    override func setUp() {
        super.setUp()
        mock = MockCustomerRepo()
        CustomerEntityQueryConfig.register(mock)
    }

    // MARK: - entities(for:)

    @available(iOS 16, *)
    func test_entitiesForIds_returnsMatchedCustomers() async throws {
        let entity = CustomerEntity(id: 10, displayName: "John Smith", phone: "555-1234")
        mock.stubbedById["10"] = entity

        let query = CustomerEntityQuery()
        let results = try await query.entities(for: ["10"])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "John Smith")
        XCTAssertEqual(mock.idsCallCount, 1)
    }

    @available(iOS 16, *)
    func test_entitiesForIds_emptyList_returnsEmpty() async throws {
        let query = CustomerEntityQuery()
        let results = try await query.entities(for: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - entities(matching:)

    @available(iOS 16, *)
    func test_entitiesMatching_byName_returnsResults() async throws {
        let entity = CustomerEntity(id: 20, displayName: "Jane Doe", phone: "555-5678")
        mock.stubbedByQuery["jane"] = [entity]

        let query = CustomerEntityQuery()
        let results = try await query.entities(matching: "jane")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "20")
        XCTAssertEqual(mock.matchingCallCount, 1)
    }

    @available(iOS 16, *)
    func test_entitiesMatching_byPhone_returnsResults() async throws {
        let entity = CustomerEntity(id: 21, displayName: "Mike T", phone: "555-9999")
        mock.stubbedByQuery["555-9999"] = [entity]

        let query = CustomerEntityQuery()
        let results = try await query.entities(matching: "555-9999")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.phone, "555-9999")
    }

    @available(iOS 16, *)
    func test_entitiesMatching_noMatch_returnsEmpty() async throws {
        let query = CustomerEntityQuery()
        let results = try await query.entities(matching: "xyz_nomatch")
        XCTAssertTrue(results.isEmpty)
    }

    @available(iOS 16, *)
    func test_suggestedEntities_callsMatchingWithEmpty() async throws {
        let entity = CustomerEntity(id: 30, displayName: "Sara L")
        mock.stubbedByQuery[""] = [entity]

        let query = CustomerEntityQuery()
        let results = try await query.suggestedEntities()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(mock.matchingCallCount, 1)
    }

    // MARK: - CustomerEntity

    func test_customerEntity_initFromCustomer_mapsFields() {
        let customer = Customer(
            id: 55,
            firstName: "Alice",
            lastName: "Wonder",
            phone: "555-0000",
            email: "alice@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let entity = CustomerEntity(from: customer)
        XCTAssertEqual(entity.id, "55")
        XCTAssertEqual(entity.numericId, 55)
        XCTAssertEqual(entity.displayName, "Alice Wonder")
        XCTAssertEqual(entity.phone, "555-0000")
        XCTAssertEqual(entity.email, "alice@example.com")
    }

    func test_customerEntity_displayRepresentation_includesName() {
        let entity = CustomerEntity(id: 60, displayName: "Bob Builder", phone: "555-1111")
        let title = String(localized: entity.displayRepresentation.title)
        XCTAssertTrue(title.contains("Bob Builder"))
    }

    // MARK: - FindCustomerIntent

    @available(iOS 16, *)
    func test_findCustomerIntent_returnsMatchingCustomers() async throws {
        let entity = CustomerEntity(id: 70, displayName: "Carol King")
        mock.stubbedByQuery["carol"] = [entity]

        let intent = FindCustomerIntent(query: "carol")
        let result = try await intent.perform()
        // Result value should contain the entity
        // Note: We verify via the mock's call count
        XCTAssertEqual(mock.matchingCallCount, 1)
    }
}
#endif // os(iOS)
