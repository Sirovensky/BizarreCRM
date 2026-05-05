import XCTest
import CoreBluetooth
@testable import Hardware

// MARK: - BluetoothDeviceTests
//
// Tests for `BluetoothDevice` immutable value + `DeviceKind` model.

final class BluetoothDeviceTests: XCTestCase {

    // MARK: - Helpers

    private static func makeDevice(
        id: UUID = UUID(),
        name: String = "Test Device",
        rssi: Int = -60,
        services: [CBUUID] = [],
        isConnected: Bool = false,
        kind: DeviceKind? = .unknown
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: name,
            rssi: rssi,
            services: services,
            isConnected: isConnected,
            kind: kind
        )
    }

    // MARK: - withConnected (immutable update)

    func test_withConnected_true_returnsNewInstance_withConnectedTrue() {
        let original = Self.makeDevice(isConnected: false)
        let updated = original.withConnected(true)

        XCTAssertFalse(original.isConnected, "Original must be unchanged")
        XCTAssertTrue(updated.isConnected, "Updated must be connected")
        XCTAssertEqual(original.id, updated.id, "ID must be preserved")
        XCTAssertEqual(original.name, updated.name, "Name must be preserved")
        XCTAssertEqual(original.rssi, updated.rssi, "RSSI must be preserved")
    }

    func test_withConnected_false_returnsNewInstance_withConnectedFalse() {
        let original = Self.makeDevice(isConnected: true)
        let updated = original.withConnected(false)

        XCTAssertTrue(original.isConnected, "Original must remain connected")
        XCTAssertFalse(updated.isConnected)
    }

    func test_withConnected_preservesKind() {
        let original = Self.makeDevice(kind: .scale)
        let updated = original.withConnected(true)
        XCTAssertEqual(updated.kind, .scale)
    }

    // MARK: - withName (immutable update)

    func test_withName_returnsNewInstance_withNewName() {
        let original = Self.makeDevice(name: "Old Name")
        let updated = original.withName("New Name")

        XCTAssertEqual(original.name, "Old Name", "Original must be unchanged")
        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(original.id, updated.id, "ID must be preserved")
    }

    func test_withName_preservesAllOtherFields() {
        let id = UUID()
        let services = [CBUUID(string: "181D")]
        let original = BluetoothDevice(
            id: id,
            name: "Old",
            rssi: -55,
            services: services,
            isConnected: true,
            kind: .scale
        )
        let updated = original.withName("New")

        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.rssi, -55)
        XCTAssertEqual(updated.isConnected, true)
        XCTAssertEqual(updated.kind, .scale)
    }

    // MARK: - withRSSI (immutable update)

    func test_withRSSI_returnsNewInstance_withNewRSSI() {
        let original = Self.makeDevice(rssi: -70)
        let updated = original.withRSSI(-45)

        XCTAssertEqual(original.rssi, -70, "Original must be unchanged")
        XCTAssertEqual(updated.rssi, -45)
        XCTAssertEqual(original.id, updated.id)
    }

    func test_withRSSI_preservesAllOtherFields() {
        let id = UUID()
        let original = BluetoothDevice(
            id: id,
            name: "Scanner",
            rssi: -80,
            services: [],
            isConnected: false,
            kind: .scanner
        )
        let updated = original.withRSSI(-50)

        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.name, "Scanner")
        XCTAssertEqual(updated.isConnected, false)
        XCTAssertEqual(updated.kind, .scanner)
    }

    // MARK: - Hashable / Equatable (id-based)

    func test_equality_basedOnId() {
        let id = UUID()
        let a = BluetoothDevice(id: id, name: "A", rssi: -60, services: [], isConnected: false, kind: .unknown)
        let b = BluetoothDevice(id: id, name: "B", rssi: -70, services: [], isConnected: true, kind: .scale)
        XCTAssertEqual(a, b, "BluetoothDevice equality is identity (id) only")
    }

    func test_inequality_differentIds() {
        let a = Self.makeDevice(id: UUID())
        let b = Self.makeDevice(id: UUID())
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_setDeduplicate() {
        let id = UUID()
        let a = BluetoothDevice(id: id, name: "A", rssi: -60, services: [], isConnected: false, kind: nil)
        let b = BluetoothDevice(id: id, name: "B", rssi: -80, services: [], isConnected: true, kind: .scale)
        let set: Set<BluetoothDevice> = [a, b]
        XCTAssertEqual(set.count, 1, "Two devices with same id should deduplicate in a Set")
    }

    // MARK: - DeviceKind CaseIterable

    func test_deviceKind_allCases_hasExpectedCount() {
        // scale, scanner, receiptPrinter, drawer, cardReader, unknown
        XCTAssertEqual(DeviceKind.allCases.count, 6)
    }

    func test_deviceKind_allCases_rawValuesAreUnique() {
        let rawValues = DeviceKind.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        XCTAssertEqual(rawValues.count, unique.count, "DeviceKind raw values must all be unique")
    }

    func test_deviceKind_scale_rawValue() {
        XCTAssertEqual(DeviceKind.scale.rawValue, "scale")
    }

    func test_deviceKind_unknown_rawValue() {
        XCTAssertEqual(DeviceKind.unknown.rawValue, "unknown")
    }

    // MARK: - nil kind

    func test_nilKind_roundTripsViaWithConnected() {
        let original = BluetoothDevice(id: UUID(), name: "X", rssi: -60, services: [], isConnected: false, kind: nil)
        let updated = original.withConnected(true)
        XCTAssertNil(updated.kind, "nil kind must survive withConnected")
    }
}
