@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - BluetoothAuthorizationStatus

public enum BluetoothAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case allowedAlways

    init(from cbStatus: CBManagerAuthorization) {
        switch cbStatus {
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        case .allowedAlways: self = .allowedAlways
        @unknown default:    self = .notDetermined
        }
    }
}

// MARK: - BluetoothManagerError

public enum BluetoothManagerError: Error, LocalizedError, Sendable {
    case bluetoothOff
    case unauthorized(BluetoothAuthorizationStatus)
    case deviceNotFound(UUID)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Bluetooth is turned off. Enable it in Settings to connect hardware."
        case .unauthorized(let status):
            return "Bluetooth access is \(status). Allow access in Settings → Privacy → Bluetooth."
        case .deviceNotFound(let id):
            return "Peripheral \(id) was not found in the discovered device list."
        case .connectionFailed(let detail):
            return "Bluetooth connection failed: \(detail)"
        }
    }
}

// MARK: - CBCentralManagerProtocol (abstraction for testability)

/// Protocol over `CBCentralManager` so unit tests can inject a mock.
public protocol CBCentralManagerProtocol: AnyObject, Sendable {
    var state: CBManagerState { get }
    var authorization: CBManagerAuthorization { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

extension CBCentralManager: CBCentralManagerProtocol {}

// MARK: - BluetoothManager

/// Central coordinator for all Bluetooth peripheral discovery and connection.
///
/// Designed as an `actor` so internal state mutations are always serialised.
/// Observation via `@Observable` is deliberately skipped here because actors
/// cannot conform to `@Observable` directly — consumers bridge discovered
/// devices through `AsyncStream` or via the `discovered` property queried
/// from the main actor where needed.
///
/// Thread-safety: all mutations happen inside the actor; delegate callbacks
/// from `CBCentralManagerDelegate` marshal back onto the actor via
/// `Task { await manager.… }`.
///
/// Info.plist requirement: `NSBluetoothAlwaysUsageDescription` must be present
/// (written by `scripts/write-info-plist.sh`). Without it iOS 13+ will crash
/// at `CBCentralManager` initialisation.
public actor BluetoothManager: NSObject {

    // MARK: - Public state

    public private(set) var discovered: [BluetoothDevice] = []
    public private(set) var isBluetoothEnabled: Bool = false
    public private(set) var authorizationStatus: BluetoothAuthorizationStatus = .notDetermined

    // MARK: - Private state

    private let central: CBCentralManagerProtocol
    private var peripheralMap: [UUID: CBPeripheral] = [:]

    // MARK: - Init

    /// Designated init. Injects the central manager for testability.
    /// Production callers omit `central` and receive a real `CBCentralManager`.
    public init(central: CBCentralManagerProtocol? = nil) {
        if let supplied = central {
            self.central = supplied
        } else {
            // `CBCentralManager` calls delegate on main queue by default; we
            // create it with a nil queue so CoreBluetooth assigns the main thread,
            // matching the expected dispatch behaviour on real hardware.
            let real = CBCentralManager()
            self.central = real
        }
        super.init()
        // Wire delegate if using real CBCentralManager.
        if let real = self.central as? CBCentralManager {
            real.delegate = self
        }
        self.isBluetoothEnabled = self.central.state == .poweredOn
        self.authorizationStatus = BluetoothAuthorizationStatus(from: self.central.authorization)
    }

    // MARK: - Public API

    /// Begin scanning for peripherals advertising the given service UUIDs.
    /// Passing `nil` scans for all devices (battery-intensive; use only in Settings).
    public func startScan(serviceUUIDs: [CBUUID]? = BluetoothDeviceProfile.scanServiceUUIDs) async {
        guard central.state == .poweredOn else {
            AppLog.hardware.warning("BluetoothManager.startScan called while not powered on (state=\(String(describing: self.central.state).lowercased()))")
            return
        }
        central.scanForPeripherals(withServices: serviceUUIDs, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        AppLog.hardware.info("BluetoothManager: scanning started")
    }

    /// Stop an in-progress scan.
    public func stopScan() {
        central.stopScan()
        AppLog.hardware.info("BluetoothManager: scanning stopped")
    }

    /// Connect to a previously-discovered peripheral by its identifier UUID.
    public func connect(to deviceId: UUID) async throws {
        guard central.state == .poweredOn else { throw BluetoothManagerError.bluetoothOff }
        guard let peripheral = peripheralMap[deviceId] else {
            throw BluetoothManagerError.deviceNotFound(deviceId)
        }
        central.connect(peripheral, options: nil)
        AppLog.hardware.info("BluetoothManager: connecting to \(deviceId)")
    }

    /// Cancel connection to a peripheral (graceful).
    public func disconnect(_ deviceId: UUID) async {
        guard let peripheral = peripheralMap[deviceId] else { return }
        central.cancelPeripheralConnection(peripheral)
        AppLog.hardware.info("BluetoothManager: disconnecting \(deviceId)")
    }

    // MARK: - Internal update methods (called from delegate)

    func _storePeripheral(_ peripheral: CBPeripheral) {
        peripheralMap[peripheral.identifier] = peripheral
    }

    func _didUpdateState(_ state: CBManagerState) {
        isBluetoothEnabled = (state == .poweredOn)
        authorizationStatus = BluetoothAuthorizationStatus(from: central.authorization)
        AppLog.hardware.info("BluetoothManager: central state → \(String(describing: state).lowercased())")
    }

    func _didDiscover(
        peripheralId: UUID,
        name: String,
        services: [CBUUID],
        rssi: Int,
        isConnected: Bool
    ) {
        let kind = BluetoothDeviceProfile.kind(for: services, name: name) ?? .unknown

        if let idx = discovered.firstIndex(where: { $0.id == peripheralId }) {
            discovered[idx] = discovered[idx].withRSSI(rssi)
        } else {
            let device = BluetoothDevice(
                id: peripheralId,
                name: name,
                rssi: rssi,
                services: services,
                isConnected: isConnected,
                kind: kind
            )
            discovered.append(device)
        }
    }

    func _didConnect(peripheralId: UUID) {
        updateConnectionState(for: peripheralId, connected: true)
    }

    func _didDisconnect(peripheralId: UUID) {
        updateConnectionState(for: peripheralId, connected: false)
    }

    // MARK: - Private helpers

    private func updateConnectionState(for id: UUID, connected: Bool) {
        guard let idx = discovered.firstIndex(where: { $0.id == id }) else { return }
        discovered[idx] = discovered[idx].withConnected(connected)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { await _didUpdateState(state) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Extract only Sendable values before hopping to the actor.
        let peripheralId = peripheral.identifier
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let rssiInt = RSSI.intValue
        let isConnected = peripheral.state == .connected
        // Store peripheral reference on the actor for later connect/disconnect calls.
        let p = UncheckedSendable(peripheral)
        let s = UncheckedSendable(services)
        Task {
            await _storePeripheral(p.value)
            await _didDiscover(
                peripheralId: peripheralId,
                name: name,
                services: s.value,
                rssi: rssiInt,
                isConnected: isConnected
            )
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peripheralId = peripheral.identifier
        Task { await _didConnect(peripheralId: peripheralId) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let peripheralId = peripheral.identifier
        Task { await _didDisconnect(peripheralId: peripheralId) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let peripheralId = peripheral.identifier
        let desc = error?.localizedDescription ?? "unknown"
        AppLog.hardware.error("BluetoothManager: failed to connect \(peripheralId) — \(desc)")
        Task { await _didDisconnect(peripheralId: peripheralId) }
    }
}

// MARK: - UncheckedSendable wrapper

/// Wraps a non-Sendable value for safe transfer across concurrency boundaries
/// when we know access is correctly serialised by the actor.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
