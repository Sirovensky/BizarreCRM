import XCTest
@testable import Hardware

// MARK: - BluetoothDeviceManagerTests
//
// Uses `MockBluetoothDeviceManager` to test the manager's business logic without
// a live CoreBluetooth stack. BluetoothDeviceManager(actor) itself is exercised
// through its public API contract.

final class BluetoothDeviceManagerTests: XCTestCase {

    // MARK: - MockBluetoothDeviceManager — initial state

    func test_mock_initiallyEmpty() {
        let mock = MockBluetoothDeviceManager()
        XCTAssertTrue(mock.pairedDevices.isEmpty)
        XCTAssertTrue(mock.discoveredDevices.isEmpty)
        XCTAssertTrue(mock.isBluetoothEnabled)
    }

    // MARK: - pair

    func test_pair_addsPairedDevice() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()

        try await mock.pair(device)

        XCTAssertEqual(mock.pairedDevices.count, 1)
        XCTAssertEqual(mock.pairedDevices.first?.id, device.id)
        XCTAssertEqual(mock.pairedDevices.first?.name, device.name)
    }

    func test_pair_incrementsCallCount() async throws {
        let mock = MockBluetoothDeviceManager()
        try await mock.pair(Self.sampleDevice())
        try await mock.pair(Self.sampleDevice(id: UUID()))
        XCTAssertEqual(mock.pairCallCount, 2)
    }

    func test_pair_recordsLastPairedDevice() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()
        try await mock.pair(device)
        XCTAssertEqual(mock.lastPairedDevice?.id, device.id)
    }

    func test_pair_throwsInjectedError() async {
        let mock = MockBluetoothDeviceManager()
        mock.pairError = BluetoothManagerError.bluetoothOff
        do {
            try await mock.pair(Self.sampleDevice())
            XCTFail("Expected error")
        } catch BluetoothManagerError.bluetoothOff {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_pair_doesNotAddDeviceWhenErrorThrown() async {
        let mock = MockBluetoothDeviceManager()
        mock.pairError = BluetoothManagerError.bluetoothOff
        _ = try? await mock.pair(Self.sampleDevice())
        XCTAssertTrue(mock.pairedDevices.isEmpty)
    }

    // MARK: - forget

    func test_forget_removesDevice() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()
        try await mock.pair(device)
        await mock.forget(device.id)
        XCTAssertTrue(mock.pairedDevices.isEmpty)
    }

    func test_forget_incrementsCallCount() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()
        try await mock.pair(device)
        await mock.forget(device.id)
        await mock.forget(UUID()) // non-existent id
        XCTAssertEqual(mock.forgetCallCount, 2)
    }

    func test_forget_recordsLastForgottenId() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()
        try await mock.pair(device)
        await mock.forget(device.id)
        XCTAssertEqual(mock.lastForgottenId, device.id)
    }

    func test_forget_unknownId_doesNotCrash() async {
        let mock = MockBluetoothDeviceManager()
        await mock.forget(UUID()) // should not throw or crash
        XCTAssertEqual(mock.forgetCallCount, 1)
    }

    // MARK: - reconnect

    func test_reconnect_callsThrough() async throws {
        let mock = MockBluetoothDeviceManager()
        let id = UUID()
        try await mock.reconnect(id)
        XCTAssertEqual(mock.reconnectCallCount, 1)
        XCTAssertEqual(mock.lastReconnectedId, id)
    }

    func test_reconnect_throwsInjectedError() async {
        let mock = MockBluetoothDeviceManager()
        mock.reconnectError = BluetoothManagerError.deviceNotFound(UUID())
        do {
            try await mock.reconnect(UUID())
            XCTFail("Expected error")
        } catch BluetoothManagerError.deviceNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - rename

    func test_rename_updatesName() async throws {
        let mock = MockBluetoothDeviceManager()
        let device = Self.sampleDevice()
        try await mock.pair(device)

        await mock.rename(device.id, to: "My Scale")

        XCTAssertEqual(mock.pairedDevices.first?.name, "My Scale")
    }

    func test_rename_incrementsCallCount() async {
        let mock = MockBluetoothDeviceManager()
        await mock.rename(UUID(), to: "A")
        await mock.rename(UUID(), to: "B")
        XCTAssertEqual(mock.renameCallCount, 2)
    }

    func test_rename_recordsLastRename() async {
        let mock = MockBluetoothDeviceManager()
        let id = UUID()
        await mock.rename(id, to: "Front Scale")
        XCTAssertEqual(mock.lastRenamedId, id)
        XCTAssertEqual(mock.lastRenamedTo, "Front Scale")
    }

    // MARK: - PairedDevice immutable helpers

    func test_pairedDevice_withName_createsNewInstance() {
        let original = PairedDevice(id: UUID(), name: "Original", kind: .scale)
        let updated = original.withName("Renamed")
        XCTAssertEqual(original.name, "Original", "Original must be unchanged")
        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(original.id, updated.id, "ID must be preserved")
        XCTAssertEqual(original.kind, updated.kind)
    }

    func test_pairedDevice_withKind_createsNewInstance() {
        let original = PairedDevice(id: UUID(), name: "Device", kind: .unknown)
        let updated = original.withKind(.scale)
        XCTAssertEqual(original.kind, .unknown, "Original must be unchanged")
        XCTAssertEqual(updated.kind, .scale)
    }

    func test_pairedDevice_roundTripsJSON() throws {
        let original = PairedDevice(
            id: UUID(),
            name: "Dymo M5",
            kind: .scale,
            pairedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PairedDevice.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.kind, .scale)
    }

    func test_pairedDevice_nilKind_roundTripsJSON() throws {
        let original = PairedDevice(id: UUID(), name: "Unknown", kind: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PairedDevice.self, from: data)
        XCTAssertNil(decoded.kind)
    }

    // MARK: - DeviceKind Codable

    func test_deviceKind_allCases_roundTripJSON() throws {
        for kind in DeviceKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(DeviceKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    // MARK: - Helpers

    private static func sampleDevice(id: UUID = UUID()) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: "Dymo M5",
            rssi: -60,
            services: [],
            isConnected: false,
            kind: .scale
        )
    }
}
