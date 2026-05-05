@preconcurrency import CoreBluetooth
import Foundation

// MARK: - Known service UUID catalog

/// Maps well-known Bluetooth service UUIDs to semantic `DeviceKind`s.
///
/// Sources:
///  - Bluetooth SIG GATT service list (https://www.bluetooth.com/specifications/assigned-numbers/)
///  - Socket Mobile CHS 7Ci datasheet (SPP UUID)
///  - Star Micronics BSC10U datasheet
///  - APG Series 4000 drawer controller
///  - Ingenico Move/5000 mobile terminal spec
public enum BluetoothDeviceProfile {

    // MARK: - Canonical service UUIDs

    /// Bluetooth SIG Weight Scale Service (§17.6).
    nonisolated(unsafe) public static let weightScaleService = CBUUID(string: "181D")

    /// Socket Mobile CHS 7Ci serial-port profile (SPP) UUID.
    nonisolated(unsafe) public static let socketMobileScannerSPP = CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB")

    /// Star Micronics BSC10U receipt printer service UUID.
    nonisolated(unsafe) public static let starMicronicsPrinter = CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB")
    // NOTE: Star and Socket Mobile both use generic SPP (0x1101) over RFCOMM.
    // Disambiguation is done by peripheral name prefix matching below.

    /// Generic Serial Port Profile (SPP) UUID — used by many classic BT devices.
    nonisolated(unsafe) public static let spp = CBUUID(string: "1101")

    /// APG cash drawer controller BLE service.
    /// APG Series 4000 does not broadcast a custom service UUID over BLE;
    /// the drawer trigger is delivered via ESC/POS over the printer bus.
    /// This placeholder is for potential future APG BLE-only drawer models.
    nonisolated(unsafe) public static let apgDrawerService = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")

    /// Ingenico mobile card reader service UUID (from Ingenico BLE SDK header).
    nonisolated(unsafe) public static let ingenicoCardReader = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")

    // MARK: - Resolution

    /// Infer the `DeviceKind` from a set of service UUIDs advertised by a peripheral.
    /// Returns `nil` when no match is found (caller may fall back to `.unknown`).
    ///
    /// Uses `CBUUID` equality which handles 16-bit ↔ 128-bit Bluetooth Base UUID
    /// equivalence correctly (e.g. `0x181D == 0000181D-0000-1000-8000-00805F9B34FB`).
    public static func kind(for serviceUUIDs: [CBUUID], name: String = "") -> DeviceKind? {
        // Weight scale — SIG 0x181D is unambiguous.
        if serviceUUIDs.contains(weightScaleService) {
            return .scale
        }

        // Ingenico card reader — proprietary UUID.
        if serviceUUIDs.contains(ingenicoCardReader) {
            return .cardReader
        }

        // APG drawer BLE service — proprietary UUID.
        if serviceUUIDs.contains(apgDrawerService) {
            return .drawer
        }

        // SPP-based devices are disambiguated by peripheral name prefix.
        // Both the 16-bit (0x1101) and 128-bit form are tested via CBUUID equality.
        if serviceUUIDs.contains(spp) || serviceUUIDs.contains(socketMobileScannerSPP) {
            let lowName = name.lowercased()
            if lowName.hasPrefix("socket") || lowName.hasPrefix("chs") {
                return .scanner
            }
            if lowName.hasPrefix("star") || lowName.hasPrefix("bsc") || lowName.hasPrefix("tsp") || lowName.hasPrefix("mpop") {
                return .receiptPrinter
            }
            if lowName.hasPrefix("apg") || lowName.hasPrefix("vasario") {
                return .drawer
            }
            // Generic SPP — unknown role without name hint.
            return .unknown
        }

        return nil
    }

    /// All service UUIDs worth scanning for (passed to `CBCentralManager.scanForPeripherals`).
    public static var scanServiceUUIDs: [CBUUID] {
        [
            weightScaleService,
            spp,
            apgDrawerService,
            ingenicoCardReader
        ]
    }
}
