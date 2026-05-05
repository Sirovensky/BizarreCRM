import XCTest
@testable import Core

// §31 Test Fixtures Helpers — FixtureLoader Tests
// Covers: successful load, typed decode, raw dict load, raw data load,
// missing-file error, malformed-type error, non-object top-level error.

final class FixtureLoaderTests: XCTestCase {

    // MARK: — Subject

    /// Returns a loader backed by the test bundle (Bundle.module in SPM).
    private func makeLoader() -> FixtureLoader {
        FixtureLoader(bundle: Bundle.module)
    }

    // MARK: — loadData

    func test_loadData_existingFile_returnsNonEmptyData() throws {
        let loader = makeLoader()
        let data = try loader.loadData("customer_default")
        XCTAssertFalse(data.isEmpty, "Expected non-empty data for existing fixture")
    }

    // MARK: — loadRaw

    func test_loadRaw_existingFile_returnsDictionary() throws {
        let loader = makeLoader()
        let dict = try loader.loadRaw("customer_default")
        XCTAssertEqual(dict["firstName"] as? String, "Alice")
        XCTAssertEqual(dict["lastName"] as? String, "Smith")
        XCTAssertEqual(dict["id"] as? Int, 1)
    }

    func test_loadRaw_envelopeFile_containsSuccessKey() throws {
        let loader = makeLoader()
        let dict = try loader.loadRaw("envelope_success")
        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertNotNil(dict["data"])
    }

    // MARK: — load (typed)

    func test_load_typed_decodesCustomer() throws {
        let loader = makeLoader()
        let customer: FixtureCustomer = try loader.load("customer_default")
        XCTAssertEqual(customer.id, 1)
        XCTAssertEqual(customer.firstName, "Alice")
        XCTAssertEqual(customer.lastName, "Smith")
        XCTAssertEqual(customer.email, "alice@example.com")
    }

    func test_load_typed_decodesDate() throws {
        let loader = makeLoader()
        let customer: FixtureCustomer = try loader.load("customer_default")
        // 2024-01-15T00:00:00Z
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: customer.createdAt)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: — Error: missing file

    func test_loadData_missingFile_throwsFileNotFound() {
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.loadData("does_not_exist_fixture")) { error in
            guard case FixtureLoader.LoaderError.fileNotFound(let name, _) = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
            XCTAssertEqual(name, "does_not_exist_fixture")
        }
    }

    func test_loadRaw_missingFile_throwsFileNotFound() {
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.loadRaw("ghost_file")) { error in
            guard case FixtureLoader.LoaderError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }

    func test_load_typed_missingFile_throwsFileNotFound() {
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.load("absent") as FixtureCustomer) { error in
            guard case FixtureLoader.LoaderError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }

    // MARK: — Error: decoding type mismatch

    func test_load_typed_wrongType_throwsDecodingFailed() {
        // customer_default is a Customer object, not a FixtureScalar (Int)
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.load("customer_default") as FixtureScalar) { error in
            guard case FixtureLoader.LoaderError.decodingFailed(let name, _, _) = error else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
            XCTAssertEqual(name, "customer_default")
        }
    }

    // MARK: — Error descriptions are informative

    func test_fileNotFoundError_descriptionMentionsFileName() {
        let err = FixtureLoader.LoaderError.fileNotFound(name: "my_fixture", bundle: "CoreTests")
        XCTAssertTrue(err.description.contains("my_fixture"), "Description should mention file name")
        XCTAssertTrue(err.description.contains("CoreTests"), "Description should mention bundle")
        XCTAssertTrue(err.description.lowercased().contains("bundle"), "Description should mention bundle keyword")
    }

    func test_decodingFailedError_descriptionMentionsTypeName() {
        let underlying = NSError(domain: "test", code: 0)
        let err = FixtureLoader.LoaderError.decodingFailed(name: "foo", type: "BarType", underlying: underlying)
        XCTAssertTrue(err.description.contains("foo"))
        XCTAssertTrue(err.description.contains("BarType"))
    }

    func test_notAnObjectError_descriptionMentionsFileName() {
        let err = FixtureLoader.LoaderError.notAnObject(name: "array_fixture")
        XCTAssertTrue(err.description.contains("array_fixture"))
    }
}

// MARK: — Local helpers (not imported from production code)

/// Minimal Decodable customer for fixture loading tests (avoids Core model coupling).
private struct FixtureCustomer: Decodable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String?
    let createdAt: Date
}

/// A scalar type used to force a deliberate decode failure in tests.
private struct FixtureScalar: Decodable {
    let value: Int
}
