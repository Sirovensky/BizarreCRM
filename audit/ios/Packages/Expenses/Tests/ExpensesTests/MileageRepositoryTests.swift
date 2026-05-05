import XCTest
@testable import Expenses

// MARK: - Stub repository (struct for simplicity in unit tests)

private struct StubMileageRepository: MileageRepository {
    let result: Result<MileageEntry, Error>

    func create(_ body: CreateMileageBody) async throws -> MileageEntry {
        switch result {
        case .success(let e): return e
        case .failure(let e): throw e
        }
    }
}

// MARK: - Fixtures

private extension MileageEntry {
    static func fixture(id: Int64 = 1, miles: Double = 10.0, totalCents: Int = 670) -> MileageEntry {
        MileageEntry(
            id: id,
            employeeId: 42,
            fromLocation: "123 Main St",
            toLocation: "456 Oak Ave",
            miles: miles,
            rateCentsPerMile: 67,
            totalCents: totalCents,
            date: "2026-04-26"
        )
    }
}

// MARK: - MileageRepositoryTests

final class MileageRepositoryTests: XCTestCase {

    // MARK: - Protocol conformance

    func test_liveMileageRepository_conformsToProtocol() {
        let _: any MileageRepository = LiveMileageRepository(api: .shared)
        XCTAssert(true, "LiveMileageRepository conforms to MileageRepository")
    }

    // MARK: - Success path

    func test_create_returnsEntryOnSuccess() async throws {
        let expected = MileageEntry.fixture(id: 7, miles: 15.0, totalCents: 1005)
        let stub = StubMileageRepository(result: .success(expected))

        let body = makebody()
        let entry = try await stub.create(body)

        XCTAssertEqual(entry.id, 7)
        XCTAssertEqual(entry.miles, 15.0, accuracy: 0.001)
    }

    // MARK: - Failure path

    func test_create_throwsOnNetworkError() async {
        let stub = StubMileageRepository(result: .failure(URLError(.notConnectedToInternet)))
        let body = makebody()
        do {
            _ = try await stub.create(body)
            XCTFail("Expected throw")
        } catch let e as URLError {
            XCTAssertEqual(e.code, .notConnectedToInternet)
        }
    }

    // MARK: - MileageEntry model

    func test_mileageEntry_allFields() {
        let entry = MileageEntry(
            id: 99,
            employeeId: 7,
            fromLocation: "Home",
            toLocation: "Office",
            fromLat: 37.7,
            fromLon: -122.4,
            toLat: 37.8,
            toLon: -122.3,
            miles: 8.5,
            rateCentsPerMile: 67,
            totalCents: 570,
            date: "2026-04-01",
            purpose: "Client visit",
            createdAt: "2026-04-01T09:00:00Z"
        )
        XCTAssertEqual(entry.id, 99)
        XCTAssertEqual(entry.fromLocation, "Home")
        XCTAssertEqual(entry.miles, 8.5, accuracy: 0.001)
        XCTAssertEqual(entry.purpose, "Client visit")
        XCTAssertEqual(entry.createdAt, "2026-04-01T09:00:00Z")
    }

    func test_mileageEntry_optionalFieldsDefaultNil() {
        let entry = MileageEntry.fixture()
        XCTAssertNil(entry.fromLat)
        XCTAssertNil(entry.fromLon)
        XCTAssertNil(entry.toLat)
        XCTAssertNil(entry.toLon)
        XCTAssertNil(entry.purpose)
        XCTAssertNil(entry.createdAt)
    }

    // MARK: - CreateMileageBody encoding

    func test_createMileageBody_encodesCodingKeys() throws {
        let body = CreateMileageBody(
            employeeId: 3,
            fromLocation: "From",
            toLocation: "To",
            fromLat: 1.0,
            fromLon: 2.0,
            toLat: 3.0,
            toLon: 4.0,
            miles: 12.5,
            rateCentsPerMile: 67,
            totalCents: 838,
            date: "2026-04-26",
            purpose: "Test"
        )
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(dict["employee_id"],      "employee_id must be snake_case")
        XCTAssertNotNil(dict["from_location"],    "from_location must be snake_case")
        XCTAssertNotNil(dict["to_location"],      "to_location must be snake_case")
        XCTAssertNotNil(dict["rate_cents_per_mile"], "rate_cents_per_mile must be snake_case")
        XCTAssertNotNil(dict["total_cents"],      "total_cents must be snake_case")
        XCTAssertNil(dict["employeeId"],          "camelCase must not leak to JSON")
        XCTAssertNil(dict["fromLocation"],        "camelCase must not leak to JSON")
    }

    // MARK: - MileageEntry Equatable + Identifiable

    func test_mileageEntry_equatable() {
        let a = MileageEntry.fixture(id: 5)
        let b = MileageEntry.fixture(id: 5)
        XCTAssertEqual(a, b)
    }

    func test_mileageEntry_identifiable() {
        let entry = MileageEntry.fixture(id: 42)
        XCTAssertEqual(entry.id, 42)
    }

    // MARK: - MileageEntryViewModel — repository injection

    @MainActor
    func test_viewModel_isNotValidWhenEmpty() {
        let stub = StubMileageRepository(result: .failure(URLError(.unknown)))
        let vm = MileageEntryViewModel(employeeId: 1, repository: stub)
        XCTAssertFalse(vm.isValid, "Empty locations make form invalid")
    }

    @MainActor
    func test_viewModel_isNotValidWhenNoCoords() {
        let stub = StubMileageRepository(result: .failure(URLError(.unknown)))
        let vm = MileageEntryViewModel(employeeId: 1, repository: stub)
        vm.fromLocation = "A"
        vm.toLocation = "B"
        // computedMiles == 0 because no lat/lon set → no haversine calc
        XCTAssertFalse(vm.isValid, "Zero miles makes form invalid even with locations set")
    }

    @MainActor
    func test_viewModel_formattedTotal_zeroWhenNoMiles() {
        let stub = StubMileageRepository(result: .failure(URLError(.unknown)))
        let vm = MileageEntryViewModel(employeeId: 1, repository: stub)
        let total = vm.formattedTotal
        // Should be some formatted string (locale-dependent); just check it doesn't crash.
        XCTAssertFalse(total.isEmpty)
    }

    // MARK: - Helpers

    private func makebody() -> CreateMileageBody {
        CreateMileageBody(
            employeeId: 42,
            fromLocation: "A",
            toLocation: "B",
            miles: 5.0,
            rateCentsPerMile: 67,
            totalCents: 335,
            date: "2026-04-26",
            purpose: nil
        )
    }
}
