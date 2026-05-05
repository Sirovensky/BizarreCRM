import XCTest
@testable import Pos
import Networking

// MARK: - Test helpers

private struct MockPickerError: Error, LocalizedError {
    var errorDescription: String? { "Network failure" }
}

/// Stub repository that returns a preset result.
private final class StubPickerRepository: PosDevicePickerRepository, @unchecked Sendable {
    enum Stub {
        case success([PosDeviceOption])
        case failure(Error)
    }

    let stub: Stub

    init(_ stub: Stub) {
        self.stub = stub
    }

    func fetchAssets(customerId: Int64) async throws -> [PosDeviceOption] {
        switch stub {
        case .success(let options):
            return options
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - PosDevicePickerRepositoryImplTests

/// Tests that `PosDevicePickerRepositoryImpl` correctly maps raw `AssetRow`
/// JSON into `PosDeviceOption` values and always appends the two sentinels.
final class PosDevicePickerRepositoryImplTests: XCTestCase {

    // MARK: - Mock API client local to these tests

    /// Returns a fixed JSON payload for any path containing "/assets".
    private final class AssetsAPIClient: APIClient, @unchecked Sendable {
        let payload: String

        init(payload: String) { self.payload = payload }

        func get<T: Decodable & Sendable>(
            _ path: String,
            query: [URLQueryItem]?,
            as type: T.Type
        ) async throws -> T {
            guard path.contains("/assets") else { throw URLError(.badURL) }
            let data = Data(payload.utf8)
            return try JSONDecoder().decode(T.self, from: data)
        }

        func post<T: Decodable & Sendable, B: Encodable & Sendable>(
            _ path: String, body: B, as type: T.Type
        ) async throws -> T { throw URLError(.badURL) }

        func put<T: Decodable & Sendable, B: Encodable & Sendable>(
            _ path: String, body: B, as type: T.Type
        ) async throws -> T { throw URLError(.badURL) }

        func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
            _ path: String, body: B, as type: T.Type
        ) async throws -> T { throw URLError(.badURL) }

        func delete(_ path: String) async throws {}

        func getEnvelope<T: Decodable & Sendable>(
            _ path: String,
            query: [URLQueryItem]?,
            as type: T.Type
        ) async throws -> APIResponse<T> { throw URLError(.badURL) }

        func setAuthToken(_ token: String?) async {}
        func setBaseURL(_ url: URL?) async {}
        func currentBaseURL() async -> URL? { nil }
        func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
    }

    // MARK: - Test 1: empty assets → exactly 2 sentinel options

    func test_emptyAssets_returnsTwoSentinelOptions() async throws {
        let repo = PosDevicePickerRepositoryImpl(api: AssetsAPIClient(payload: "[]"))

        let options = try await repo.fetchAssets(customerId: 1)

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0], .noSpecificDevice)
        XCTAssertEqual(options[1], .addNew)
    }

    // MARK: - Test 2: N assets → N + 2 options, sentinels at tail

    func test_nonEmptyAssets_returnsNPlusTwoOptions() async throws {
        let json = """
        [
          {"id": 10, "name": "iPhone 14 Pro", "device_type": "Phone",
           "serial": "XY123", "imei": null, "color": null},
          {"id": 11, "name": "MacBook Pro 14", "device_type": "Laptop",
           "serial": null, "imei": null, "color": "Space Gray"}
        ]
        """
        let repo = PosDevicePickerRepositoryImpl(api: AssetsAPIClient(payload: json))

        let options = try await repo.fetchAssets(customerId: 42)

        // 2 real assets + noSpecificDevice + addNew
        XCTAssertEqual(options.count, 4)

        if case .asset(let id, let label, _) = options[0] {
            XCTAssertEqual(id, 10)
            XCTAssertEqual(label, "iPhone 14 Pro")
        } else {
            XCTFail("Expected .asset at index 0, got \(options[0])")
        }

        XCTAssertEqual(options[2], .noSpecificDevice)
        XCTAssertEqual(options[3], .addNew)
    }
}

// MARK: - PosDevicePickerViewModelTests

@MainActor
final class PosDevicePickerViewModelTests: XCTestCase {

    // MARK: - Test 3: successful load populates options and clears error

    func test_loadSuccess_populatesOptionsAndClearsError() async {
        let options: [PosDeviceOption] = [
            .asset(id: 5, label: "Galaxy S24", subtitle: "Android"),
            .noSpecificDevice,
            .addNew
        ]
        let vm = PosDevicePickerViewModel(
            repository: StubPickerRepository(.success(options))
        )

        await vm.load(customerId: 99)

        XCTAssertEqual(vm.options, options)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Test 4: load error sets errorMessage, falls back to 2 sentinels

    func test_loadError_setsErrorMessageAndFallsBackToSentinels() async {
        let vm = PosDevicePickerViewModel(
            repository: StubPickerRepository(.failure(MockPickerError()))
        )

        await vm.load(customerId: 7)

        XCTAssertEqual(vm.errorMessage, "Network failure")
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.options.count, 2)
        XCTAssertTrue(vm.options.contains(.noSpecificDevice))
        XCTAssertTrue(vm.options.contains(.addNew))
    }

    // MARK: - Test 5: selecting noSpecificDevice clears asset id

    func test_selectNoSpecificDevice_clearsAssetId() async {
        let vm = PosDevicePickerViewModel(
            repository: StubPickerRepository(.success([
                .asset(id: 3, label: "Pixel 8", subtitle: nil),
                .noSpecificDevice,
                .addNew
            ]))
        )
        await vm.load(customerId: 1)

        // Pick a real asset first, confirm asset id is set.
        vm.select(.asset(id: 3, label: "Pixel 8", subtitle: nil))
        XCTAssertEqual(vm.selectedAssetId, 3)

        // Pick "no specific device" — asset id must be nil.
        vm.select(.noSpecificDevice)
        XCTAssertNil(vm.selectedAssetId,
            "selectedAssetId must be nil when noSpecificDevice is selected")
    }

    // MARK: - Test 6: selecting an asset populates selectedAssetId

    func test_selectAsset_setsSelectedAssetId() async {
        let vm = PosDevicePickerViewModel(
            repository: StubPickerRepository(.success([
                .asset(id: 77, label: "iPad Pro 12.9", subtitle: "Tablet"),
                .noSpecificDevice,
                .addNew
            ]))
        )
        await vm.load(customerId: 2)

        vm.select(.asset(id: 77, label: "iPad Pro 12.9", subtitle: "Tablet"))

        XCTAssertEqual(vm.selectedAssetId, 77)
        XCTAssertEqual(vm.selected,
            .asset(id: 77, label: "iPad Pro 12.9", subtitle: "Tablet"))
    }

    // MARK: - Test 7: clearSelection resets selected to nil

    func test_clearSelection_resetsSelected() async {
        let vm = PosDevicePickerViewModel(
            repository: StubPickerRepository(.success([.noSpecificDevice, .addNew]))
        )
        await vm.load(customerId: 3)
        vm.select(.noSpecificDevice)
        XCTAssertNotNil(vm.selected)

        vm.clearSelection()

        XCTAssertNil(vm.selected)
        XCTAssertNil(vm.selectedAssetId)
    }
}

// MARK: - PosDeviceAttachmentTests

final class PosDeviceAttachmentTests: XCTestCase {

    // MARK: - Test 8: nil deviceOptionId marks attachment as unspecified

    func test_attachment_nilDeviceOptionId_isUnspecified() {
        let id = UUID()
        let attachment = PosDeviceAttachment(cartLineId: id, deviceOptionId: nil)
        XCTAssertTrue(attachment.isUnspecified)
        XCTAssertNil(attachment.deviceOptionId)
        XCTAssertEqual(attachment.cartLineId, id)
    }

    // MARK: - Test 9: non-nil deviceOptionId is not unspecified

    func test_attachment_nonNilDeviceOptionId_isNotUnspecified() {
        let attachment = PosDeviceAttachment(cartLineId: UUID(), deviceOptionId: 42)
        XCTAssertFalse(attachment.isUnspecified)
        XCTAssertEqual(attachment.deviceOptionId, 42)
    }
}

// MARK: - PosDeviceOptionTests

final class PosDeviceOptionTests: XCTestCase {

    func test_assetId_returnsId() {
        let option = PosDeviceOption.asset(id: 99, label: "iPhone", subtitle: nil)
        XCTAssertEqual(option.assetId, 99)
    }

    func test_assetId_nilForSentinels() {
        XCTAssertNil(PosDeviceOption.noSpecificDevice.assetId)
        XCTAssertNil(PosDeviceOption.addNew.assetId)
    }

    func test_identifiable_uniqueIds() {
        let a = PosDeviceOption.asset(id: 1, label: "A", subtitle: nil)
        let b = PosDeviceOption.asset(id: 2, label: "B", subtitle: nil)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(
            PosDeviceOption.noSpecificDevice.id,
            PosDeviceOption.addNew.id
        )
    }

    func test_equatable_sameAssetIdIsEqual() {
        let opt1 = PosDeviceOption.asset(id: 5, label: "X", subtitle: nil)
        let opt2 = PosDeviceOption.asset(id: 5, label: "X", subtitle: nil)
        XCTAssertEqual(opt1, opt2)
    }

    func test_equatable_differentAssetIdsNotEqual() {
        let opt1 = PosDeviceOption.asset(id: 1, label: "X", subtitle: nil)
        let opt2 = PosDeviceOption.asset(id: 2, label: "X", subtitle: nil)
        XCTAssertNotEqual(opt1, opt2)
    }
}
