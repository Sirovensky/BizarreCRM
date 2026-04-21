import XCTest
@testable import Camera

/// Tests for ``PhotoStore`` — covers stage / promote / discard / list lifecycle.
///
/// Each test creates an isolated `PhotoStore` rooted under a unique temporary
/// subdirectory and cleans up in `tearDown` so parallel runs don't interfere.
final class PhotoStoreTests: XCTestCase {

    // MARK: - Fixtures

    private var testRoot: URL!
    private var store: PhotoStore!

    override func setUp() async throws {
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        store = try PhotoStore()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testRoot)
    }

    // MARK: - Helper

    private func sampleData(size: Int = 64) -> Data {
        Data(repeating: 0xFF, count: size)
    }

    // MARK: - stage(data:)

    func test_stage_writesFileToStagingDirectory() async throws {
        let data = sampleData()
        let url = try await store.stage(data: data)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Staged file must exist on disk")
        XCTAssertEqual(try Data(contentsOf: url), data,
                       "Staged file content must match input data")
    }

    func test_stage_generatesUniqueURLsForEachCall() async throws {
        let url1 = try await store.stage(data: sampleData())
        let url2 = try await store.stage(data: sampleData())

        XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent,
                          "Each staged file must have a unique name")
    }

    func test_stage_filenameHasHeicExtension() async throws {
        let url = try await store.stage(data: sampleData())
        XCTAssertEqual(url.pathExtension, "heic",
                       "Staged files must use .heic extension")
    }

    // MARK: - discard(staged:)

    func test_discard_removesFile() async throws {
        let url = try await store.stage(data: sampleData())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try await store.discard(staged: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Discarded file must be removed from disk")
    }

    func test_discard_isNoOpForNonExistentFile() async throws {
        let phantom = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghost-\(UUID().uuidString).heic")
        // Must not throw.
        try await store.discard(staged: phantom)
    }

    // MARK: - promote(staged:entity:id:)

    func test_promote_movesFileToEntityDirectory() async throws {
        let data = sampleData()
        let staged = try await store.stage(data: data)

        let permanent = try await store.promote(staged: staged, entity: "ticket", id: 42)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path),
                       "Staged URL must not exist after promote")
        XCTAssertTrue(FileManager.default.fileExists(atPath: permanent.path),
                      "Permanent URL must exist after promote")
        XCTAssertEqual(try Data(contentsOf: permanent), data,
                       "Promoted file content must match original data")
    }

    func test_promote_urlContainsEntityAndId() async throws {
        let staged = try await store.stage(data: sampleData())
        let permanent = try await store.promote(staged: staged, entity: "customer", id: 99)

        XCTAssertTrue(permanent.path.contains("customer"),
                      "Permanent path must contain entity name")
        XCTAssertTrue(permanent.path.contains("99"),
                      "Permanent path must contain entity id")
    }

    // MARK: - listForEntity(_:id:)

    func test_list_returnsEmptyForUnknownEntity() async throws {
        let urls = try await store.listForEntity("ticket", id: 1)
        XCTAssertTrue(urls.isEmpty)
    }

    func test_list_returnsAllPromotedFiles() async throws {
        let entity = "ticket"
        let id: Int64 = 7

        let data1 = sampleData(size: 10)
        let data2 = sampleData(size: 20)

        let staged1 = try await store.stage(data: data1)
        let staged2 = try await store.stage(data: data2)

        _ = try await store.promote(staged: staged1, entity: entity, id: id)
        _ = try await store.promote(staged: staged2, entity: entity, id: id)

        let urls = try await store.listForEntity(entity, id: id)
        XCTAssertEqual(urls.count, 2, "Both promoted files should appear in listing")
    }
}
