@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - BluetoothBackgroundManager
//
// §17 Bluetooth — "Maintain connection across app backgrounding (required for POS)"
//                + "Register bluetooth-central background mode"
//
// CoreBluetooth `bluetooth-central` background mode (UIBackgroundModes key) allows
// the app to:
//  1. Receive connection events while backgrounded.
//  2. Be relaunched by the OS to handle a central-manager state restoration if the
//     app was terminated while maintaining a peripheral connection.
//
// IMPORTANT: The UIBackgroundModes entry `"bluetooth-central"` must be added to
// Info.plist by `scripts/write-info-plist.sh` and the `project.yml`
// `UIBackgroundModes` key (Agent 10 owns both). This file provides the Swift-side
// restoration handler; the entitlement must be present for it to take effect.
//
// State restoration flow:
//  • OS terminates the app while a peripheral connection is active.
//  • App relaunches in background; OS calls `centralManager(_:willRestoreState:)`.
//  • `BluetoothRestorationHandler.restore(state:manager:)` re-hydrates the
//    `BluetoothManager` with the previously-connected peripherals so POS and
//    print jobs can resume without the user re-pairing.
//
// Background scan — for POS we only keep previously-paired peripherals connected;
// we do NOT scan in background (battery drain). Scanning is foreground-only.

// MARK: - BluetoothBackgroundManager

/// Handles CoreBluetooth state restoration for `bluetooth-central` background mode.
///
/// Instantiate once in `AppServices` and retain it for the app lifetime.
/// Wire into `CBCentralManager` by passing `CBCentralManagerOptionRestoreIdentifierKey`
/// when creating the manager.
///
/// Note: `bluetooth-central` must be listed in `UIBackgroundModes` in Info.plist.
/// Agent 10 owns `scripts/write-info-plist.sh` — see Discovered section in `agents.md`
/// for the ticket to add this key.
public final class BluetoothBackgroundManager: NSObject, @unchecked Sendable {

    // MARK: - Types

    /// Restoration identifier — must match the value used when creating `CBCentralManager`.
    public static let restoreIdentifier = "com.bizarrecrm.hardware.bluetooth-central"

    // MARK: - Singleton

    public static let shared = BluetoothBackgroundManager()

    // MARK: - Private state

    private var onRestored: (([CBPeripheral]) -> Void)?
    private var onConnectionEvent: ((CBPeripheral, CBConnectionEvent) -> Void)?

    // MARK: - Init

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Register a handler called when the OS restores a previous Bluetooth session.
    ///
    /// - Parameter handler: Receives the list of previously-connected peripherals.
    ///   The caller should re-subscribe to characteristics and update
    ///   `BluetoothManager.discovered` accordingly.
    public func onStateRestored(_ handler: @escaping @Sendable ([CBPeripheral]) -> Void) {
        self.onRestored = handler
    }

    /// Register a handler for `CBConnectionEvent` (iOS 13+ connection monitoring).
    ///
    /// `CBCentralManager.registerForConnectionEvents(options:)` fires this when a
    /// paired peripheral connects / disconnects even while the app is in the background.
    public func onConnectionEvent(_ handler: @escaping @Sendable (CBPeripheral, CBConnectionEvent) -> Void) {
        self.onConnectionEvent = handler
    }

    // MARK: - Internal (called by CBCentralManagerDelegate)

    /// Called from `centralManager(_:willRestoreState:)`.
    ///
    /// Extracts the list of peripherals CoreBluetooth was managing on behalf of
    /// this app before termination, then calls the registered restoration handler.
    func handleWillRestoreState(_ dict: [String: Any], manager: CBCentralManager) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        AppLog.hardware.info("BluetoothBackgroundManager: restoring \(peripherals.count) peripheral(s)")
        for peripheral in peripherals {
            AppLog.hardware.info("  - \(peripheral.name ?? "unnamed", privacy: .public) (\(peripheral.identifier))")
        }
        onRestored?(peripherals)
    }

    /// Called from `centralManager(_:connectionEventDidOccur:for:)`.
    func handleConnectionEvent(_ event: CBConnectionEvent, peripheral: CBPeripheral) {
        AppLog.hardware.info("BluetoothBackgroundManager: connectionEvent=\(event.rawValue) for \(peripheral.name ?? "unnamed", privacy: .public)")
        onConnectionEvent?(peripheral, event)
    }
}

// MARK: - Background scan guard

/// Enforces the "no background scan" policy.
///
/// CoreBluetooth will scan in background if `CBCentralManagerScanOptionAllowDuplicatesKey`
/// is set AND the background mode is active. We explicitly guard against this so
/// scanning only happens while the app is in the foreground.
public enum BluetoothScanPolicy: Sendable {

    /// Returns `true` when background scanning is permitted (always `false` for us).
    ///
    /// The POS only needs to keep existing connections alive in background; it does
    /// not need to discover new peripherals. Background scanning is battery-intensive
    /// and unnecessary.
    public static let allowsBackgroundScan: Bool = false

    /// The scan options dictionary to pass to `CBCentralManager.scanForPeripherals`.
    ///
    /// `CBCentralManagerScanOptionAllowDuplicatesKey: false` — no duplicate events.
    /// We never pass `true` as that enables continuous background scanning.
    public static let defaultScanOptions: [String: Any] = [
        CBCentralManagerScanOptionAllowDuplicatesKey: false
    ]
}

// MARK: - Discovered note for Agent 10
//
// Add `bluetooth-central` to `UIBackgroundModes` array in
// `scripts/write-info-plist.sh` under the `UIBackgroundModes` key:
//
//   echo "  <key>UIBackgroundModes</key>" >> "$PLIST"
//   echo "  <array>" >> "$PLIST"
//   echo "    <string>bluetooth-central</string>" >> "$PLIST"
//   echo "    <string>fetch</string>" >> "$PLIST"
//   echo "    <string>remote-notification</string>" >> "$PLIST"
//   echo "    <string>processing</string>" >> "$PLIST"
//   echo "  </array>" >> "$PLIST"
//
// Also add `CBCentralManagerOptionRestoreIdentifierKey: BluetoothBackgroundManager.restoreIdentifier`
// to the `CBCentralManager` init options in `BluetoothManager`.
// This is a project.yml + Info.plist change → Agent 10 (advisory lock).
// Filed in agents.md Discovered section.
