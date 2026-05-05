#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - Stub PosDevicePickerRepository (local to this file)

/// Used by the device-picker tests in this file only. The DevicePicker tests
/// in DevicePicker/ define their own copy — duplication is intentional to
/// keep each test file self-contained.
private struct StubDevicePickerError: Error, LocalizedError {
    var errorDescription: String? { "Stub network failure" }
}

private final class StubDeviceRepo: PosDevicePickerRepository, @unchecked Sendable {
    enum Stub {
        case success([PosDeviceOption])
        case failure(Error)
    }
    let stub: Stub
    init(_ stub: Stub) { self.stub = stub }

    func fetchAssets(customerId: Int64) async throws -> [PosDeviceOption] {
        switch stub {
        case .success(let opts): return opts
        case .failure(let e):   throw e
        }
    }
}

// MARK: - PosRepairDevicePickerViewModelTests

@MainActor
final class PosRepairDevicePickerViewModelTests: XCTestCase {

    // MARK: - Test 1: selecting a saved device sets `selected` and unblocks Continue CTA

    func test_selectSavedDevice_setsSelectedAndUnblocksContinue() async {
        let savedDevice = PosDeviceOption.asset(id: 55, label: "iPhone 15 Pro", subtitle: "Phone")
        let repo = StubDeviceRepo(.success([savedDevice, .noSpecificDevice, .addNew]))
        let vm = PosDevicePickerViewModel(repository: repo)

        await vm.load(customerId: 10)
        vm.select(savedDevice)

        XCTAssertEqual(vm.selected, savedDevice,
            "selected must be updated after calling select(_:)")
        XCTAssertEqual(vm.selectedAssetId, 55,
            "selectedAssetId must reflect the chosen asset's id")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Test 2: tapping "Add new device" sets selected to .addNew

    func test_selectAddNew_routesToAddNew() async {
        let repo = StubDeviceRepo(.success([.noSpecificDevice, .addNew]))
        let vm = PosDevicePickerViewModel(repository: repo)

        await vm.load(customerId: 1)
        vm.select(.addNew)

        XCTAssertEqual(vm.selected, .addNew,
            "Tapping Add new device must set selected to .addNew sentinel")
        XCTAssertNil(vm.selectedAssetId,
            "selectedAssetId must be nil for the .addNew sentinel")
    }

    // MARK: - Test 3: empty saved-devices list still allows manual entry (.noSpecificDevice)

    func test_emptySavedDevices_stillAllowsManualEntryPath() async {
        // Server returns empty array; repository appends the two sentinels.
        // Simulate this: stub returns only the two sentinel options.
        let repo = StubDeviceRepo(.success([.noSpecificDevice, .addNew]))
        let vm = PosDevicePickerViewModel(repository: repo)

        await vm.load(customerId: 2)

        // Even with no real assets the sheet must still show the two sentinels.
        XCTAssertTrue(vm.options.contains(.noSpecificDevice),
            "noSpecificDevice sentinel must always be present")
        XCTAssertTrue(vm.options.contains(.addNew),
            "addNew sentinel must always be present")

        // Selecting noSpecificDevice is a valid selection path.
        vm.select(.noSpecificDevice)
        XCTAssertEqual(vm.selected, .noSpecificDevice)
        XCTAssertNil(vm.selectedAssetId,
            "selectedAssetId is nil for noSpecificDevice (no asset to attach)")
    }

    // MARK: - Test 4: clearSelection resets selected back to nil

    func test_clearSelection_resetsToNil() async {
        let repo = StubDeviceRepo(.success([
            .asset(id: 77, label: "iPad Air", subtitle: "Tablet"),
            .noSpecificDevice,
            .addNew
        ]))
        let vm = PosDevicePickerViewModel(repository: repo)

        await vm.load(customerId: 3)
        vm.select(.asset(id: 77, label: "iPad Air", subtitle: "Tablet"))
        XCTAssertNotNil(vm.selected)

        vm.clearSelection()

        XCTAssertNil(vm.selected, "clearSelection must set selected to nil")
        XCTAssertNil(vm.selectedAssetId)
    }

    // MARK: - Test 5: load error falls back to two sentinels

    func test_loadError_fallsBackToSentinels() async {
        let repo = StubDeviceRepo(.failure(StubDevicePickerError()))
        let vm = PosDevicePickerViewModel(repository: repo)

        await vm.load(customerId: 99)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.options.count, 2)
        XCTAssertTrue(vm.options.contains(.noSpecificDevice))
        XCTAssertTrue(vm.options.contains(.addNew))
        XCTAssertFalse(vm.isLoading)
    }
}
#endif
