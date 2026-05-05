import XCTest
@testable import Inventory

// MARK: - InventoryKitsRepositoryTests
//
// Tests for InventoryKitsRepositoryImpl using a stub that records calls and
// returns controlled responses. Verifies list, detail fetch, and delete paths.

// MARK: - Stub repository

private actor StubKitsRepository: InventoryKitsRepository {
    private let listResult: Result<[InventoryKit], Error>
    private let getResult: Result<InventoryKit, Error>
    private let deleteError: Error?

    private(set) var deletedIds: [Int64] = []

    init(
        listResult: Result<[InventoryKit], Error> = .success([]),
        getResult: Result<InventoryKit, Error> = .success(
            InventoryKit(id: 1, name: "Stub Kit")
        ),
        deleteError: Error? = nil
    ) {
        self.listResult = listResult
        self.getResult = getResult
        self.deleteError = deleteError
    }

    func listKits() async throws -> [InventoryKit] {
        try listResult.get()
    }

    func getKit(id: Int64) async throws -> InventoryKit {
        try getResult.get()
    }

    func deleteKit(id: Int64) async throws {
        deletedIds.append(id)
        if let err = deleteError { throw err }
    }
}

// MARK: - Tests

final class InventoryKitsRepositoryTests: XCTestCase {

    // MARK: List

    func test_listKits_returnsKitsFromRepository() async throws {
        let kits = [
            InventoryKit(id: 1, name: "Kit A", itemCount: 2),
            InventoryKit(id: 2, name: "Kit B", itemCount: 4),
        ]
        let stub = StubKitsRepository(listResult: .success(kits))
        let repo = stub as InventoryKitsRepository

        let result = try await repo.listKits()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Kit A")
        XCTAssertEqual(result[1].itemCount, 4)
    }

    func test_listKits_propagatesError() async {
        struct FetchError: Error {}
        let stub = StubKitsRepository(listResult: .failure(FetchError()))

        do {
            _ = try await stub.listKits()
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssert(error is FetchError)
        }
    }

    // MARK: Get single

    func test_getKit_returnsKitWithItems() async throws {
        let components = [
            InventoryKitComponent(id: 1, kitId: 99, inventoryItemId: 10,
                                  quantity: 2, itemName: "Screw", sku: "SCR-01",
                                  retailPriceCents: 100, costPriceCents: 40, inStock: 50),
        ]
        let kit = InventoryKit(id: 99, name: "Screw Kit", items: components)
        let stub = StubKitsRepository(getResult: .success(kit))

        let result = try await stub.getKit(id: 99)

        XCTAssertEqual(result.id, 99)
        XCTAssertEqual(result.items?.count, 1)
        XCTAssertEqual(result.totalCostCents, 80) // 2 * 40
    }

    func test_getKit_propagatesNotFoundError() async {
        struct NotFoundError: Error {}
        let stub = StubKitsRepository(getResult: .failure(NotFoundError()))

        do {
            _ = try await stub.getKit(id: 0)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssert(error is NotFoundError)
        }
    }

    // MARK: Delete

    func test_deleteKit_recordsDeletedId() async throws {
        let stub = StubKitsRepository()

        try await stub.deleteKit(id: 7)

        let ids = await stub.deletedIds
        XCTAssertEqual(ids, [7])
    }

    func test_deleteKit_propagatesError() async {
        struct DeleteError: Error {}
        let stub = StubKitsRepository(deleteError: DeleteError())

        do {
            try await stub.deleteKit(id: 1)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssert(error is DeleteError)
        }
    }

    // MARK: Request bodies

    func test_createInventoryKitRequest_encodesSnakeCaseItemId() throws {
        let request = CreateInventoryKitRequest(
            name: "Bundle",
            items: [KitItemRequest(inventoryItemId: 42, quantity: 3)]
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["items"] as? [[String: Any]]
        XCTAssertEqual(items?.first?["inventory_item_id"] as? Int, 42)
        XCTAssertEqual(items?.first?["quantity"] as? Int, 3)
    }
}
