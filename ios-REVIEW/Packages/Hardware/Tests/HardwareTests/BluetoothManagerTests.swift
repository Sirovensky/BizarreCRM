import XCTest
import CoreBluetooth
@testable import Hardware

// MARK: - Mock CBCentralManager

/// In-memory mock that records calls without touching real CoreBluetooth.
final class MockCBCentralManager: CBCentralManagerProtocol, @unchecked Sendable {

    // Settable state
    var state: CBManagerState = .unknown
    var authorization: CBManagerAuthorization = .notDetermined

    // Call recording
    var scanCalled = false
    var stopScanCalled = false
    var connectCalled = false
    var disconnectCalled = false
    var lastScannedUUIDs: [CBUUID]?
    var lastConnectedPeripheral: CBPeripheral?
    var lastDisconnectedPeripheral: CBPeripheral?

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanCalled = true
        lastScannedUUIDs = serviceUUIDs
    }

    func stopScan() { stopScanCalled = true }

    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalled = true
        lastConnectedPeripheral = peripheral
    }

    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        disconnectCalled = true
        lastDisconnectedPeripheral = peripheral
    }
}

// MARK: - BluetoothManagerTests

final class BluetoothManagerTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isBluetoothEnabled_false_whenUnknown() async {
        let mock = MockCBCentralManager()
        mock.state = .unknown
        let manager = BluetoothManager(central: mock)
        let enabled = await manager.isBluetoothEnabled
        XCTAssertFalse(enabled)
    }

    func test_initialState_isBluetoothEnabled_true_whenPoweredOn() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOn
        let manager = BluetoothManager(central: mock)
        let enabled = await manager.isBluetoothEnabled
        XCTAssertTrue(enabled)
    }

    func test_initialState_discoveredDevices_empty() async {
        let mock = MockCBCentralManager()
        let manager = BluetoothManager(central: mock)
        let devices = await manager.discovered
        XCTAssertTrue(devices.isEmpty)
    }

    // MARK: - startScan

    func test_startScan_doesNotCallScan_whenNotPoweredOn() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOff
        let manager = BluetoothManager(central: mock)
        await manager.startScan(serviceUUIDs: nil)
        XCTAssertFalse(mock.scanCalled)
    }

    func test_startScan_callsScan_whenPoweredOn() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOn
        let manager = BluetoothManager(central: mock)
        await manager.startScan(serviceUUIDs: [CBUUID(string: "181D")])
        XCTAssertTrue(mock.scanCalled)
        XCTAssertEqual(mock.lastScannedUUIDs, [CBUUID(string: "181D")])
    }

    // MARK: - stopScan

    func test_stopScan_callsStopScan() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOn
        let manager = BluetoothManager(central: mock)
        await manager.stopScan()
        XCTAssertTrue(mock.stopScanCalled)
    }

    // MARK: - connect

    func test_connect_throwsBluetoothOff_whenNotPoweredOn() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOff
        let manager = BluetoothManager(central: mock)
        do {
            try await manager.connect(to: UUID())
            XCTFail("Expected BluetoothManagerError.bluetoothOff")
        } catch BluetoothManagerError.bluetoothOff {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_connect_throwsDeviceNotFound_forUnknownUUID() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOn
        let manager = BluetoothManager(central: mock)
        let fakeID = UUID()
        do {
            try await manager.connect(to: fakeID)
            XCTFail("Expected BluetoothManagerError.deviceNotFound")
        } catch BluetoothManagerError.deviceNotFound(let id) {
            XCTAssertEqual(id, fakeID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - _didUpdateState

    func test_didUpdateState_poweredOn_setsIsBluetoothEnabled() async {
        let mock = MockCBCentralManager()
        mock.state = .unknown
        mock.authorization = .notDetermined
        let manager = BluetoothManager(central: mock)
        await manager._didUpdateState(.poweredOn)
        let enabled = await manager.isBluetoothEnabled
        XCTAssertTrue(enabled)
    }

    func test_didUpdateState_poweredOff_clearsIsBluetoothEnabled() async {
        let mock = MockCBCentralManager()
        mock.state = .poweredOn
        let manager = BluetoothManager(central: mock)
        await manager._didUpdateState(.poweredOff)
        let enabled = await manager.isBluetoothEnabled
        XCTAssertFalse(enabled)
    }

    // MARK: - Authorization status

    func test_authorizationStatus_mapsCorrectly_denied() async {
        let mock = MockCBCentralManager()
        mock.authorization = .denied
        let manager = BluetoothManager(central: mock)
        let status = await manager.authorizationStatus
        XCTAssertEqual(status, .denied)
    }

    func test_authorizationStatus_mapsCorrectly_allowedAlways() async {
        let mock = MockCBCentralManager()
        mock.authorization = .allowedAlways
        let manager = BluetoothManager(central: mock)
        let status = await manager.authorizationStatus
        XCTAssertEqual(status, .allowedAlways)
    }

    // MARK: - Error descriptions

    func test_errorDescriptions_areNonEmpty() {
        XCTAssertNotNil(BluetoothManagerError.bluetoothOff.errorDescription)
        XCTAssertNotNil(BluetoothManagerError.unauthorized(.denied).errorDescription)
        XCTAssertNotNil(BluetoothManagerError.deviceNotFound(UUID()).errorDescription)
        XCTAssertNotNil(BluetoothManagerError.connectionFailed("oops").errorDescription)
    }
}
