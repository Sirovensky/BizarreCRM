@preconcurrency import CoreBluetooth
import Foundation

// MARK: - DeviceKind

/// Semantic classification inferred from Bluetooth service UUIDs.
public enum DeviceKind: String, Sendable, CaseIterable, Hashable {
    case scale
    case scanner
    case receiptPrinter
    case drawer
    case cardReader
    case unknown
}

// MARK: - BluetoothDevice

/// Immutable value representing a discovered BLE/classic peripheral.
public struct BluetoothDevice: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let services: [CBUUID]
    public let isConnected: Bool
    /// Inferred semantic role; `nil` when UUIDs don't match any known profile.
    public let kind: DeviceKind?

    public init(
        id: UUID,
        name: String,
        rssi: Int,
        services: [CBUUID],
        isConnected: Bool,
        kind: DeviceKind?
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.services = services
        self.isConnected = isConnected
        self.kind = kind
    }

    // MARK: Hashable / Equatable — based on stable `id`
    public static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Mutation helpers (immutable pattern)

    public func withConnected(_ connected: Bool) -> BluetoothDevice {
        BluetoothDevice(
            id: id, name: name, rssi: rssi,
            services: services, isConnected: connected, kind: kind
        )
    }

    public func withName(_ newName: String) -> BluetoothDevice {
        BluetoothDevice(
            id: id, name: newName, rssi: rssi,
            services: services, isConnected: isConnected, kind: kind
        )
    }

    public func withRSSI(_ newRSSI: Int) -> BluetoothDevice {
        BluetoothDevice(
            id: id, name: name, rssi: newRSSI,
            services: services, isConnected: isConnected, kind: kind
        )
    }
}
