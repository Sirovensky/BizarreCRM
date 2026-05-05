import XCTest
@testable import Customers
import Networking

// §5.7 — CustomerAssetsViewModel unit tests.

@MainActor
final class CustomerAssetsViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeAsset(
        id: Int64 = 1,
        name: String = "iPhone 14 Pro",
        deviceType: String? = "Phone",
        serial: String? = "XYZ123"
    ) -> CustomerAsset {
        CustomerAsset(
            id: id,
            customerId: 42,
            name: name,
            deviceType: deviceType,
            serial: serial,
            createdAt: "2024-01-01T00:00:00Z"
        )
    }

    // MARK: - list-load

    func test_load_populatesAssets() async {
        let assets = [makeAsset(id: 1), makeAsset(id: 2, name: "iPad Air")]
        let repo = StubAssetsRepository(fetchResult: .success(assets))
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)

        await vm.load()

        XCTAssertEqual(vm.assets.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_setsErrorMessageOnFailure() async {
        let repo = StubAssetsRepository(fetchResult: .failure(APITransportError.httpStatus(500, message: "Server error")))
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)

        await vm.load()

        XCTAssertTrue(vm.assets.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - add

    func test_addAsset_prependsNewAssetToList() async {
        let existing = makeAsset(id: 1)
        let created = makeAsset(id: 99, name: "MacBook Pro")
        let repo = StubAssetsRepository(
            fetchResult: .success([existing]),
            addResult: .success(created)
        )
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)
        await vm.load()

        vm.addName = "MacBook Pro"
        vm.addDeviceType = "Laptop"
        let ok = await vm.addAsset()

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.assets.count, 2)
        XCTAssertEqual(vm.assets.first?.name, "MacBook Pro")
        XCTAssertNil(vm.errorMessage)
    }

    func test_addAsset_withEmptyName_returnsfalse_andDoesNotCallRepository() async {
        let repo = StubAssetsRepository()
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)
        vm.addName = "   "

        let ok = await vm.addAsset()

        XCTAssertFalse(ok)
        XCTAssertEqual(repo.addCallCount, 0)
        XCTAssertTrue(vm.assets.isEmpty)
    }

    func test_addAsset_setsErrorOnRepositoryFailure() async {
        let repo = StubAssetsRepository(
            fetchResult: .success([]),
            addResult: .failure(APITransportError.httpStatus(422, message: "Name required"))
        )
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)
        vm.addName = "Valid Name"

        let ok = await vm.addAsset()

        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - empty state

    func test_emptyState_afterLoad_assetsIsEmpty() async {
        let repo = StubAssetsRepository(fetchResult: .success([]))
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)

        await vm.load()

        XCTAssertTrue(vm.assets.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - remove

    func test_remove_deletesAssetLocally() async {
        let a1 = makeAsset(id: 1)
        let a2 = makeAsset(id: 2, name: "iPad")
        let repo = StubAssetsRepository(fetchResult: .success([a1, a2]))
        let vm = CustomerAssetsViewModel(repository: repo, customerId: 42)
        await vm.load()

        vm.remove(a1)

        XCTAssertEqual(vm.assets.count, 1)
        XCTAssertEqual(vm.assets.first?.id, 2)
    }
}

// MARK: - StubAssetsRepository

final class StubAssetsRepository: CustomerAssetsRepository, @unchecked Sendable {
    private let fetchResult: Result<[CustomerAsset], Error>?
    private let addResult: Result<CustomerAsset, Error>?
    private(set) var addCallCount: Int = 0

    init(
        fetchResult: Result<[CustomerAsset], Error>? = nil,
        addResult: Result<CustomerAsset, Error>? = nil
    ) {
        self.fetchResult = fetchResult
        self.addResult = addResult
    }

    func fetchAssets(customerId: Int64) async throws -> [CustomerAsset] {
        switch fetchResult {
        case .success(let assets): return assets
        case .failure(let err):    throw err
        case .none:                return []
        }
    }

    func addAsset(customerId: Int64, request: CreateCustomerAssetRequest) async throws -> CustomerAsset {
        addCallCount += 1
        switch addResult {
        case .success(let asset): return asset
        case .failure(let err):   throw err
        case .none:               throw APITransportError.noBaseURL
        }
    }
}
