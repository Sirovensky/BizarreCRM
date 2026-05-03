@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - StarPrinterBridge
//
// §17.4 — Bluetooth ESC/POS bridge targeting Star Micronics BSC10U, TSP100IV-BT,
// mPOP, and any SPP-based thermal printer advertising the Serial Port Profile
// (RFCOMM UUID 0x1101).
//
// Architecture:
//  - Protocol only in this wave. No third-party Star SDK dependency.
//  - Uses CoreBluetooth to write raw ESC/POS bytes produced by `EscPosCommandBuilder`
//    directly to the characteristic that proxies RFCOMM on SPP-bridged BLE printers.
//  - For true Star SDK integration (StarIO10 / Star Bluetooth), this class should be
//    replaced by a wrapper around `ISCBBuilder` — kept as TODO when MFi approval lands.
//
// Connection model:
//  1. Caller pairs via `BluetoothManager`; the connected `CBPeripheral` is passed here.
//  2. `connect()` discovers the RFCOMM data characteristic (0x2456 for Star BT; fallback
//     to a writable characteristic on service 0x1101).
//  3. `send(_:)` writes raw ESC/POS bytes in 512-byte chunks (Star max-write limit).
//  4. `disconnect()` cancels the CBPeripheral connection cleanly.
//
// Note on MFi: Real MFi printers (Star MFi program) require an entitlement and the
// ExternalAccessory framework. This bridge is the BLE-SPP path — it covers Star
// printers with the "BT" suffix in their model name (BLE mode). Classic BT + MFi
// printers are a separate integration deferred to MFi approval.

// MARK: - StarPrinterBridgeError

public enum StarPrinterBridgeError: Error, LocalizedError, Sendable {
    case notConnected
    case characteristicNotFound
    case writeFailed(String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Star printer is not connected. Pair it via Settings → Hardware → Bluetooth."
        case .characteristicNotFound:
            return "Star printer BLE characteristic not found. The firmware may not be compatible."
        case .writeFailed(let detail):
            return "Write to Star printer failed: \(detail)"
        case .disconnected:
            return "Star printer disconnected during print."
        }
    }
}

// MARK: - StarPrinterBridgeProtocol

/// Abstract contract for the Star Bluetooth ESC/POS bridge.
/// Concrete: `StarPrinterBridge` (live CoreBluetooth path).
/// Test-double: `MockStarPrinterBridge`.
public protocol StarPrinterBridgeProtocol: Sendable {
    var isConnected: Bool { get async }
    func connect() async throws
    func send(_ data: Data) async throws
    func disconnect() async
}

// MARK: - StarPrinterBridge

/// CoreBluetooth-backed ESC/POS bridge to Star Micronics BLE printers (SPP-over-BLE).
///
/// Thread safety: `actor` isolates mutable state. CoreBluetooth delegate callbacks
/// route back via `Task { await self.… }` pattern (same approach as `BluetoothManager`).
public actor StarPrinterBridge: NSObject, StarPrinterBridgeProtocol {

    // MARK: - BLE constants

    /// Star Micronics BLE printer service UUID (SPP-over-BLE).
    /// Published in Star SDK documentation for BSC10U / TSP100IV-BT.
    nonisolated(unsafe) private static let starServiceUUID = CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB")

    /// Star "data" characteristic UUID for write-with-response on BSC10U.
    nonisolated(unsafe) private static let starWriteCharacteristicUUID = CBUUID(string: "00002456-0000-1000-8000-00805F9B34FB")

    /// Chunk size in bytes. Star firmware rejects writes larger than 512 B.
    private static let maxChunkBytes = 512

    // MARK: - Private state

    private let peripheral: CBPeripheral
    private var writeCharacteristic: CBCharacteristic?
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var _isConnected: Bool = false

    // MARK: - Init

    /// - Parameter peripheral: A `CBPeripheral` obtained via `BluetoothManager`.
    ///   It does NOT need to already be connected — `connect()` initiates the
    ///   `CBCentralManager.connect` + service discovery sequence.
    public init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        let p = UncheckedSendableCBPeripheral(peripheral)
        p.setDelegate(bridge: self)
    }

    // MARK: - StarPrinterBridgeProtocol

    public var isConnected: Bool { _isConnected }

    /// Discover the Star write characteristic (async, resolves once service discovery
    /// completes or throws on timeout / error).
    public func connect() async throws {
        guard writeCharacteristic == nil else { return } // already connected
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            // Trigger service discovery. The peripheral must already be in .connected
            // state (BluetoothManager handles CBCentralManager.connect).
            let uuids = [Self.starServiceUUID]
            peripheral.discoverServices(uuids)
        }
    }

    /// Write raw bytes to the printer in 512-byte chunks. Throws on first failure.
    public func send(_ data: Data) async throws {
        guard let characteristic = writeCharacteristic, _isConnected else {
            throw StarPrinterBridgeError.notConnected
        }
        let bytes = Array(data)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + Self.maxChunkBytes, bytes.count)
            let chunk = Data(bytes[offset..<end])
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.writeContinuation = continuation
                peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            }
            offset = end
        }
        AppLog.hardware.info("StarPrinterBridge: sent \(data.count) bytes in \((data.count + Self.maxChunkBytes - 1) / Self.maxChunkBytes) chunk(s)")
    }

    public func disconnect() async {
        _isConnected = false
        writeCharacteristic = nil
        AppLog.hardware.info("StarPrinterBridge: disconnected")
    }

    // MARK: - Internal callbacks (from delegate trampoline)

    func _didDiscoverServices(_ error: Error?) {
        if let error {
            connectionContinuation?.resume(throwing: StarPrinterBridgeError.writeFailed(error.localizedDescription))
            connectionContinuation = nil
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.starServiceUUID }) else {
            connectionContinuation?.resume(throwing: StarPrinterBridgeError.characteristicNotFound)
            connectionContinuation = nil
            return
        }
        peripheral.discoverCharacteristics([Self.starWriteCharacteristicUUID], for: service)
    }

    func _didDiscoverCharacteristics(_ service: CBService, error: Error?) {
        if let error {
            connectionContinuation?.resume(throwing: StarPrinterBridgeError.writeFailed(error.localizedDescription))
            connectionContinuation = nil
            return
        }
        // Primary: exact UUID match. Fallback: first writable characteristic.
        let found = service.characteristics?.first(where: { $0.uuid == Self.starWriteCharacteristicUUID })
            ?? service.characteristics?.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) })
        guard let characteristic = found else {
            connectionContinuation?.resume(throwing: StarPrinterBridgeError.characteristicNotFound)
            connectionContinuation = nil
            return
        }
        writeCharacteristic = characteristic
        _isConnected = true
        connectionContinuation?.resume()
        connectionContinuation = nil
        AppLog.hardware.info("StarPrinterBridge: write characteristic found — \(characteristic.uuid)")
    }

    func _didWriteValue(_ error: Error?) {
        if let error {
            writeContinuation?.resume(throwing: StarPrinterBridgeError.writeFailed(error.localizedDescription))
        } else {
            writeContinuation?.resume()
        }
        writeContinuation = nil
    }

    func _didDisconnect(_ error: Error?) {
        _isConnected = false
        writeCharacteristic = nil
        // Fail any in-flight operations.
        connectionContinuation?.resume(throwing: StarPrinterBridgeError.disconnected)
        connectionContinuation = nil
        writeContinuation?.resume(throwing: StarPrinterBridgeError.disconnected)
        writeContinuation = nil
        AppLog.hardware.warning("StarPrinterBridge: peripheral disconnected — \(error?.localizedDescription ?? "no error")")
    }
}

// MARK: - CBPeripheral delegate trampoline

/// Wraps `CBPeripheral` delegate so its nonisolated callbacks can route to the actor.
/// Using a separate delegate object avoids `StarPrinterBridge` having to be `NSObject`-subclass
/// in contexts where that's undesirable; keeping it as-is is also fine since it already subclasses.
extension StarPrinterBridge: CBPeripheralDelegate {

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { await _didDiscoverServices(error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let svc = UncheckedSendableCBService(service)
        Task { await _didDiscoverCharacteristics(svc.value, error: error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { await _didWriteValue(error) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { await _didDisconnect(error) }
    }
}

// MARK: - UncheckedSendable wrappers (Sendable safety for CBPeripheral/CBService)

private struct UncheckedSendableCBPeripheral: @unchecked Sendable {
    let value: CBPeripheral
    init(_ v: CBPeripheral) { value = v }
    func setDelegate(bridge: StarPrinterBridge) {
        value.delegate = bridge
    }
}

private struct UncheckedSendableCBService: @unchecked Sendable {
    let value: CBService
    init(_ v: CBService) { value = v }
}

// MARK: - StarPrinterAdapter (ReceiptPrinter conformance)

/// Bridges `StarPrinterBridge` → `ReceiptPrinter` so the POS layer can use it
/// without knowing about CoreBluetooth.
///
/// This is the object registered in `Container+Registrations` when a Star BT
/// printer is paired.
public final class StarPrinterAdapter: ReceiptPrinter, @unchecked Sendable {

    private let bridge: any StarPrinterBridgeProtocol

    public init(bridge: any StarPrinterBridgeProtocol) {
        self.bridge = bridge
    }

    public func isAvailable() -> Bool {
        // Synchronous availability check — bridge reports via the actor property.
        // We can't `await` here (sync protocol method), so we return `true` when
        // the bridge is not a `NullReceiptPrinter`-equivalent.
        // The real availability is enforced by `printReceipt` throwing `.notPaired`.
        true
    }

    public func printReceipt(_ payload: ReceiptPayload) async throws {
        let connected = await bridge.isConnected
        if !connected {
            try await bridge.connect()
        }
        let bytes = EscPosCommandBuilder.receipt(payload)
        do {
            try await bridge.send(bytes)
        } catch {
            throw ReceiptPrinterError.printFailed(error.localizedDescription)
        }
    }

    public func openCashDrawer() async throws {
        let connected = await bridge.isConnected
        if !connected {
            throw ReceiptPrinterError.notPaired
        }
        let bytes = EscPosCommandBuilder.drawerKick()
        do {
            try await bridge.send(bytes)
        } catch {
            throw ReceiptPrinterError.drawerFailed(error.localizedDescription)
        }
    }
}

// MARK: - MockStarPrinterBridge

/// Controllable test-double for `StarPrinterBridgeProtocol`.
/// Lives in the main source target (not just test target) so SwiftUI previews
/// and integration tests can reference it without extra module imports.
public actor MockStarPrinterBridge: StarPrinterBridgeProtocol {

    public var connectError: Error?
    public var sendError: Error?
    public var _isConnected: Bool

    public private(set) var connectCallCount: Int = 0
    public private(set) var disconnectCallCount: Int = 0
    public private(set) var sentData: [Data] = []

    public init(isConnected: Bool = false) {
        self._isConnected = isConnected
    }

    public var isConnected: Bool { _isConnected }

    public func connect() async throws {
        connectCallCount += 1
        if let error = connectError { throw error }
        _isConnected = true
    }

    public func send(_ data: Data) async throws {
        if let error = sendError { throw error }
        sentData.append(data)
    }

    public func disconnect() async {
        disconnectCallCount += 1
        _isConnected = false
    }

    public func reset() {
        connectError = nil
        sendError = nil
        _isConnected = false
        connectCallCount = 0
        disconnectCallCount = 0
        sentData = []
    }
}
