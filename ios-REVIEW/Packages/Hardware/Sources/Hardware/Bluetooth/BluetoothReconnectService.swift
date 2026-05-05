@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - BluetoothReconnectService
//
// §17.7 "Reconnect — auto-reconnect on launch; surface failures in status bar glass."
//
// Listens for Bluetooth power-on and previously-paired device events, then
// reconnects remembered peripherals automatically.
//
// Persisted peripheral identifiers are stored in UserDefaults keyed by device type
// (receipt printer BT-UUID, weight scale BT-UUID, etc.). On app launch the service
// reads those UUIDs, waits for `CBManagerState.poweredOn`, then calls
// `CBCentralManager.retrievePeripherals(withIdentifiers:)` and connects.
//
// Failures are surfaced via the published `reconnectError` property so the
// app chrome (status bar glass) can show a warning banner.

/// Auto-reconnects remembered Bluetooth peripherals when the manager powers on.
///
/// Inject this service via the app's DI container and call `start()` from
/// `AppServices.setup()` (after the DI container is ready).
public final class BluetoothReconnectService: NSObject, @unchecked Sendable {

    // MARK: - Types

    public enum ReconnectEvent: Sendable {
        case reconnecting(peripheralId: UUID, name: String?)
        case reconnected(peripheralId: UUID, name: String?)
        case failed(peripheralId: UUID, name: String?, error: Error)
    }

    // MARK: - Published observable state

    /// Latest reconnect event. Consumers on the main actor observe this to
    /// drive a status-bar glass banner.
    @MainActor public private(set) var latestEvent: ReconnectEvent?

    // MARK: - Configuration

    /// UserDefaults key prefix for remembered peripheral UUIDs.
    public static let udKeyPrefix = "com.bizarrecrm.bt.remembered."

    /// UUID → human-readable device-type label for event descriptions.
    private static let knownDeviceLabels: [CBUUID: String] = [
        CBUUID(string: "181D"): "Weight Scale",
        CBUUID(string: "1801"): "Peripheral",
    ]

    // MARK: - Private

    private var central: CBCentralManager?
    private var isStarted = false

    // MARK: - Public API

    /// Begin the reconnect lifecycle. Safe to call multiple times — re-entrancy is guarded.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        // Allocate CBCentralManager on the main queue so delegate callbacks fire there.
        let mgr = CBCentralManager(delegate: self, queue: .main)
        central = mgr
        AppLog.hardware.info("BluetoothReconnectService: started, BT state=\(String(describing: mgr.state).lowercased())")
    }

    // MARK: - Persisted UUID store

    /// Remember a peripheral UUID for a given device-type key so it reconnects on launch.
    ///
    /// - Parameters:
    ///   - uuid: The `CBPeripheral.identifier` to remember.
    ///   - key: Stable device-type key (e.g. `"weightScale"`, `"receiptPrinter"`).
    public static func remember(peripheralId uuid: UUID, forKey key: String) {
        UserDefaults.standard.set(uuid.uuidString, forKey: udKeyPrefix + key)
        AppLog.hardware.info("BluetoothReconnectService: remembered \(uuid) for key '\(key, privacy: .public)'")
    }

    /// Remove a remembered peripheral (e.g. when the user un-pairs).
    public static func forget(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: udKeyPrefix + key)
    }

    /// All remembered peripheral UUIDs persisted across launches.
    public static var allRememberedUUIDs: [UUID] {
        UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(udKeyPrefix) }
            .compactMap { _, value -> UUID? in
                guard let str = value as? String else { return nil }
                return UUID(uuidString: str)
            }
    }

    // MARK: - Reconnect

    private func reconnectAllRemembered() {
        let uuids = Self.allRememberedUUIDs
        guard !uuids.isEmpty, let central else { return }
        let peripherals = central.retrievePeripherals(withIdentifiers: uuids)
        for peripheral in peripherals {
            publishEvent(.reconnecting(peripheralId: peripheral.identifier, name: peripheral.name))
            peripheral.delegate = self
            central.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])
            AppLog.hardware.info("BluetoothReconnectService: reconnecting \(peripheral.identifier)")
        }
    }

    private func publishEvent(_ event: ReconnectEvent) {
        Task { @MainActor in
            self.latestEvent = event
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothReconnectService: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        AppLog.hardware.info("BluetoothReconnectService: central state → \(String(describing: central.state).lowercased())")
        if central.state == .poweredOn {
            reconnectAllRemembered()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        publishEvent(.reconnected(peripheralId: peripheral.identifier, name: peripheral.name))
        AppLog.hardware.info("BluetoothReconnectService: reconnected \(peripheral.identifier)")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let err = error ?? BluetoothManagerError.connectionFailed("Unknown error")
        publishEvent(.failed(peripheralId: peripheral.identifier, name: peripheral.name, error: err))
        AppLog.hardware.error("BluetoothReconnectService: failed to reconnect \(peripheral.identifier) — \(err.localizedDescription, privacy: .public)")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // Auto-retry on unexpected disconnect (error non-nil = unexpected).
        if error != nil {
            AppLog.hardware.warning("BluetoothReconnectService: unexpected disconnect \(peripheral.identifier), retrying…")
            central.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate (minimal — service-discovery not needed here)

extension BluetoothReconnectService: CBPeripheralDelegate {}
