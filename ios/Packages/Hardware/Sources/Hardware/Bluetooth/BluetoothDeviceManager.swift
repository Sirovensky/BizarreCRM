@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - PairedDevice
//
// Lightweight record persisted to UserDefaults (TODO §17: migrate to GRDB).
// Immutable value; updates produce new copies.

public struct PairedDevice: Identifiable, Sendable, Codable, Hashable {

    public let id: UUID            // CBPeripheral.identifier — stable across app launches
    public let name: String
    public let kind: DeviceKind?
    public let pairedAt: Date
    /// MAC address (colon-separated hex, e.g. "AA:BB:CC:DD:EE:FF").
    /// Populated on first connection where available via CoreBluetooth advertisement data.
    /// `nil` when the platform does not expose the MAC (iOS hides MAC by default post iOS 13).
    /// For printers, the manufacturer typically prints the MAC on the label; we display it
    /// when available so admins can configure DHCP reservations. §17: "App shows printer
    /// MAC after first connection."
    public let macAddress: String?

    public init(
        id: UUID,
        name: String,
        kind: DeviceKind?,
        pairedAt: Date = Date(),
        macAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pairedAt = pairedAt
        self.macAddress = macAddress
    }

    /// Returns a new `PairedDevice` with an updated name (immutable update).
    public func withName(_ newName: String) -> PairedDevice {
        PairedDevice(id: id, name: newName, kind: kind, pairedAt: pairedAt, macAddress: macAddress)
    }

    /// Returns a new `PairedDevice` with an updated kind (immutable update).
    public func withKind(_ newKind: DeviceKind?) -> PairedDevice {
        PairedDevice(id: id, name: name, kind: newKind, pairedAt: pairedAt, macAddress: macAddress)
    }

    /// Returns a new `PairedDevice` with an updated MAC address.
    /// Called on first connection when advertisement data contains the address.
    public func withMACAddress(_ mac: String) -> PairedDevice {
        PairedDevice(id: id, name: name, kind: kind, pairedAt: pairedAt, macAddress: mac)
    }
}

// MARK: - DeviceKind Codable conformance
// DeviceKind is a plain enum (String rawValue) so it encodes/decodes via rawValue.
extension DeviceKind: Codable {}

// MARK: - BluetoothDeviceManagerProtocol

/// Protocol over `BluetoothDeviceManager` so tests can inject a controllable mock
/// without pulling in CoreBluetooth at all.
public protocol BluetoothDeviceManagerProtocol: AnyObject, Sendable {
    /// All paired devices persisted across launches.
    var pairedDevices: [PairedDevice] { get async }
    /// Live-scanned devices (not yet paired, or updating RSSI).
    var discoveredDevices: [BluetoothDevice] { get async }
    /// True when Bluetooth is powered on.
    var isBluetoothEnabled: Bool { get async }

    /// Scan for peripherals broadcasting relevant service UUIDs.
    func startScan() async
    func stopScan() async

    /// Connect + remember: connects to the peripheral then persists the pairing record.
    func pair(_ device: BluetoothDevice) async throws

    /// Disconnect + remove the pairing record.
    func forget(_ id: UUID) async

    /// Connect to a previously-paired peripheral by its identifier.
    /// Reuses the `BluetoothManager` peripheral map if the device was seen in
    /// the current scan; otherwise requests a re-scan.
    func reconnect(_ id: UUID) async throws

    /// Rename a paired device (only affects the local record, not the hardware).
    func rename(_ id: UUID, to newName: String) async
}

// MARK: - BluetoothDeviceManager

/// Stateful coordinator that wraps `BluetoothManager` and adds:
/// - Persistence of paired devices by `CBPeripheral.identifier` UUID.
/// - Reconnect-on-launch logic for each known paired device.
/// - Forget / rename operations on the persisted record.
///
/// Thread safety: `actor`. All state mutations are serialised inside the actor.
/// The underlying `BluetoothManager` is itself an `actor`; cross-actor calls are `await`.
public actor BluetoothDeviceManager: BluetoothDeviceManagerProtocol {

    // MARK: - Persistence

    private static let defaultsKey = "com.bizarrecrm.hardware.pairedDevices"

    // MARK: - Dependencies

    private let btManager: BluetoothManager

    // MARK: - State

    public private(set) var pairedDevices: [PairedDevice] = []

    public var discoveredDevices: [BluetoothDevice] {
        get async { await btManager.discovered }
    }

    public var isBluetoothEnabled: Bool {
        get async { await btManager.isBluetoothEnabled }
    }

    // MARK: - Init

    public init(btManager: BluetoothManager = BluetoothManager()) {
        self.btManager = btManager
        // Synchronous load from UserDefaults on init (actor body, safe).
        pairedDevices = Self.loadFromDefaults()
    }

    // MARK: - Scan

    public func startScan() async {
        await btManager.startScan(serviceUUIDs: nil) // nil = all in Settings context
    }

    public func stopScan() async {
        await btManager.stopScan()
    }

    // MARK: - Pair

    /// Connect to `device` and save a `PairedDevice` record.
    public func pair(_ device: BluetoothDevice) async throws {
        try await btManager.connect(to: device.id)
        let record = PairedDevice(
            id: device.id,
            name: device.name,
            kind: device.kind,
            pairedAt: Date()
        )
        upsert(record)
        persist()
        AppLog.hardware.info("BluetoothDeviceManager: paired \(device.name, privacy: .public) (\(device.id))")
    }

    // MARK: - Forget

    /// Disconnect and remove the pairing record.
    public func forget(_ id: UUID) async {
        await btManager.disconnect(id)
        pairedDevices.removeAll { $0.id == id }
        persist()
        AppLog.hardware.info("BluetoothDeviceManager: forgot device \(id)")
    }

    // MARK: - Reconnect

    /// Attempt to reconnect to a previously-paired device.
    /// If it's not in the current discovered list, this will throw
    /// `BluetoothManagerError.deviceNotFound` — the caller should trigger a
    /// scan first and retry.
    public func reconnect(_ id: UUID) async throws {
        try await btManager.connect(to: id)
        AppLog.hardware.info("BluetoothDeviceManager: reconnected \(id)")
    }

    // MARK: - Rename

    /// Rename a paired device in the local record (no effect on hardware).
    public func rename(_ id: UUID, to newName: String) async {
        guard let idx = pairedDevices.firstIndex(where: { $0.id == id }) else { return }
        pairedDevices[idx] = pairedDevices[idx].withName(newName)
        persist()
        AppLog.hardware.info("BluetoothDeviceManager: renamed \(id) → \(newName, privacy: .public)")
    }

    // MARK: - Reconnect all on launch

    /// Call on app launch (after BT is powered on) to reconnect all saved devices.
    /// Failures are logged but not thrown — a device may simply be off.
    public func reconnectAllOnLaunch() async {
        for device in pairedDevices {
            do {
                try await reconnect(device.id)
            } catch {
                AppLog.hardware.warning("BluetoothDeviceManager: auto-reconnect failed for \(device.name, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Private helpers

    private func upsert(_ record: PairedDevice) {
        if let idx = pairedDevices.firstIndex(where: { $0.id == record.id }) {
            pairedDevices[idx] = record
        } else {
            pairedDevices.append(record)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadFromDefaults() -> [PairedDevice] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PairedDevice].self, from: data) else {
            return []
        }
        return decoded
    }
}

// MARK: - MockBluetoothDeviceManager

/// Controllable test-double for `BluetoothDeviceManagerProtocol`.
public final class MockBluetoothDeviceManager: BluetoothDeviceManagerProtocol, @unchecked Sendable {

    // MARK: Configurable state

    public var stubbedPairedDevices: [PairedDevice] = []
    public var stubbedDiscoveredDevices: [BluetoothDevice] = []
    public var stubbedIsBluetoothEnabled: Bool = true
    public var pairError: Error?
    public var reconnectError: Error?

    // MARK: Call tracking

    public private(set) var pairCallCount: Int = 0
    public private(set) var forgetCallCount: Int = 0
    public private(set) var reconnectCallCount: Int = 0
    public private(set) var renameCallCount: Int = 0
    public private(set) var lastPairedDevice: BluetoothDevice?
    public private(set) var lastForgottenId: UUID?
    public private(set) var lastReconnectedId: UUID?
    public private(set) var lastRenamedId: UUID?
    public private(set) var lastRenamedTo: String?

    // MARK: BluetoothDeviceManagerProtocol

    public var pairedDevices: [PairedDevice] { stubbedPairedDevices }
    public var discoveredDevices: [BluetoothDevice] { stubbedDiscoveredDevices }
    public var isBluetoothEnabled: Bool { stubbedIsBluetoothEnabled }

    public init() {}

    public func startScan() async {}
    public func stopScan() async {}

    public func pair(_ device: BluetoothDevice) async throws {
        pairCallCount += 1
        lastPairedDevice = device
        if let error = pairError { throw error }
        let record = PairedDevice(id: device.id, name: device.name, kind: device.kind)
        stubbedPairedDevices.append(record)
    }

    public func forget(_ id: UUID) async {
        forgetCallCount += 1
        lastForgottenId = id
        stubbedPairedDevices.removeAll { $0.id == id }
    }

    public func reconnect(_ id: UUID) async throws {
        reconnectCallCount += 1
        lastReconnectedId = id
        if let error = reconnectError { throw error }
    }

    public func rename(_ id: UUID, to newName: String) async {
        renameCallCount += 1
        lastRenamedId = id
        lastRenamedTo = newName
        if let idx = stubbedPairedDevices.firstIndex(where: { $0.id == id }) {
            stubbedPairedDevices[idx] = stubbedPairedDevices[idx].withName(newName)
        }
    }
}
