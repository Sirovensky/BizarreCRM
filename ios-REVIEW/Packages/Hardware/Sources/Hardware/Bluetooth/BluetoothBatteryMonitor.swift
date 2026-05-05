@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - BluetoothBatteryMonitor
//
// §17: "Surface peripheral battery level where published"
//      "Low-battery warning"
//      "Warn when multiple clients share one peripheral"
//
// Reads the Bluetooth SIG Battery Service (0x180F) characteristic (0x2A19)
// from connected peripherals. When a reading falls below the warning threshold
// the monitor publishes a `BluetoothBatteryWarning` for the UI to surface.
//
// "Multiple clients" detection: CoreBluetooth allows only one app to hold
// a GATT connection at a time on iOS. If a peripheral is already connected
// when we call `connect(_:)`, `centralManager(_:didConnect:)` fires immediately —
// but another app may have opened GATT services. We detect this by checking
// the peripheral state is `.connected` before we issued a connect; if so,
// `isSharedPeripheral` is set true and a warning is emitted.

// MARK: - Battery GATT constants

private extension CBUUID {
    /// Bluetooth SIG Battery Service UUID (0x180F).
    static let batteryService = CBUUID(string: "180F")
    /// Bluetooth SIG Battery Level Characteristic UUID (0x2A19).
    static let batteryLevel = CBUUID(string: "2A19")
}

// MARK: - BluetoothBatteryWarning

/// A low-battery or multi-client warning for a paired peripheral.
public struct BluetoothBatteryWarning: Sendable, Identifiable {
    public enum Kind: Sendable {
        case lowBattery(percent: Int)
        case multipleClientsDetected
    }
    public let id: UUID = UUID()
    public let peripheralId: UUID
    public let deviceName: String
    public let kind: Kind

    public var message: String {
        switch kind {
        case .lowBattery(let pct):
            return "\(deviceName) battery is low (\(pct)%). Please charge or replace the battery."
        case .multipleClientsDetected:
            return "\(deviceName) appears to be connected to another app or device. Disconnecting the other client may improve reliability."
        }
    }
}

// MARK: - BluetoothBatteryMonitor

/// Subscribes to the Battery Level characteristic on connected BLE peripherals.
///
/// Inject via DI container. Call `monitor(peripheral:)` after connection is established.
/// Observe `warnings` (main actor) to drive UI banners.
@Observable
@MainActor
public final class BluetoothBatteryMonitor {

    // MARK: - Published state

    /// Active battery warnings (low battery or multi-client). Cleared when device reconnects healthy.
    public private(set) var warnings: [BluetoothBatteryWarning] = []

    /// Battery levels keyed by peripheral UUID.
    public private(set) var batteryLevels: [UUID: Int] = [:]

    // MARK: - Configuration

    /// Battery percent below which a low-battery warning is emitted (default 20%).
    public var lowBatteryThreshold: Int = 20

    // MARK: - Internal delegates

    private var delegates: [UUID: BatteryPeripheralDelegate] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Begin monitoring the Battery Service on `peripheral` (must already be connected).
    public func monitor(peripheral: CBPeripheral, deviceName: String) {
        let delegate = BatteryPeripheralDelegate(
            peripheralId: peripheral.identifier,
            deviceName: deviceName,
            monitor: self
        )
        delegates[peripheral.identifier] = delegate
        peripheral.delegate = delegate
        peripheral.discoverServices([.batteryService])
        AppLog.hardware.info("BluetoothBatteryMonitor: discovering battery service on \(deviceName, privacy: .public)")
    }

    /// Remove monitoring for a peripheral (e.g. on disconnect).
    public func stopMonitoring(peripheralId: UUID) {
        delegates.removeValue(forKey: peripheralId)
        batteryLevels.removeValue(forKey: peripheralId)
        warnings.removeAll { $0.peripheralId == peripheralId }
    }

    /// Check if a peripheral was already connected before our app connected to it.
    /// If so, emit a multi-client warning.
    public func checkMultiClientRisk(peripheral: CBPeripheral, deviceName: String) {
        // If the peripheral's state was already `.connected` before we called connect,
        // another GATT client may be using it.
        if peripheral.state == .connected {
            let warning = BluetoothBatteryWarning(
                peripheralId: peripheral.identifier,
                deviceName: deviceName,
                kind: .multipleClientsDetected
            )
            appendWarning(warning)
            AppLog.hardware.warning("BluetoothBatteryMonitor: possible multi-client on \(deviceName, privacy: .public)")
        }
    }

    // MARK: - Internal callbacks (called from delegate)

    func didReadBattery(peripheralId: UUID, deviceName: String, percent: Int) {
        batteryLevels[peripheralId] = percent
        AppLog.hardware.info("BluetoothBatteryMonitor: \(deviceName, privacy: .public) battery=\(percent)%")
        if percent < lowBatteryThreshold {
            let warning = BluetoothBatteryWarning(
                peripheralId: peripheralId,
                deviceName: deviceName,
                kind: .lowBattery(percent: percent)
            )
            // Replace any existing low-battery warning for this device.
            warnings.removeAll { $0.peripheralId == peripheralId && {
                if case .lowBattery = $0.kind { return true }
                return false
            }($0) }
            appendWarning(warning)
        } else {
            // Clear resolved low-battery warnings.
            warnings.removeAll { $0.peripheralId == peripheralId && {
                if case .lowBattery = $0.kind { return true }
                return false
            }($0) }
        }
    }

    private func appendWarning(_ warning: BluetoothBatteryWarning) {
        warnings.removeAll { $0.peripheralId == warning.peripheralId }
        warnings.append(warning)
    }
}

// MARK: - BatteryPeripheralDelegate

/// CBPeripheralDelegate that reads the Battery Level characteristic.
private final class BatteryPeripheralDelegate: NSObject, CBPeripheralDelegate, @unchecked Sendable {

    private let peripheralId: UUID
    private let deviceName: String
    private weak var monitor: BluetoothBatteryMonitor?

    init(peripheralId: UUID, deviceName: String, monitor: BluetoothBatteryMonitor) {
        self.peripheralId = peripheralId
        self.deviceName = deviceName
        self.monitor = monitor
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        for service in peripheral.services ?? [] {
            if service.uuid == .batteryService {
                peripheral.discoverCharacteristics([.batteryLevel], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, service.uuid == .batteryService else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == .batteryLevel {
                // Read once and subscribe for notifications.
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == .batteryLevel,
              let data = characteristic.value, !data.isEmpty else { return }
        let percent = Int(data[0])
        let id = peripheralId
        let name = deviceName
        Task { @MainActor [weak monitor] in
            monitor?.didReadBattery(peripheralId: id, deviceName: name, percent: percent)
        }
    }
}
