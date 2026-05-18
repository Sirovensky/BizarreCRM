@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - BluetoothWeightScale

/// Reads weight from a BLE peripheral implementing the Bluetooth SIG
/// Weight Scale Service (0x181D) and Weight Measurement Characteristic (0x2A9D).
///
/// Specification: Bluetooth GATT Assigned Numbers — Weight Scale Service.
///
/// Characteristic 0x2A9D "Weight Measurement" encoding (little-endian):
/// ```
/// Byte 0:    Flags
///            Bit 0: Measurement Unit (0 = SI/kg, 1 = Imperial/lb)
///            Bit 1: Time stamp present
///            Bit 2: User ID present
///            Bit 3: BMI and Height present
/// Bytes 1-2: Weight (uint16, little-endian)
///            SI:       resolution 0.005 kg  → grams = value * 5
///            Imperial: resolution 0.01 lb   → grams = value * 4.536
/// (Further bytes optional per flags — ignored for now)
/// ```
public actor BluetoothWeightScale: WeightScale {

    // MARK: - Types

    /// Internal measurement unit from the characteristic flags byte.
    enum MeasurementUnit {
        case si        // kilograms
        case imperial  // pounds
    }

    // MARK: - State

    private let peripheral: CBPeripheral
    private var latestWeight: Weight?
    private var continuationTokens: [_ContinuationToken] = []

    // MARK: - Init

    /// - Parameter peripheral: A `CBPeripheral` that has already been connected
    ///   and whose Weight Scale service has been discovered.
    public init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    // MARK: - WeightScale

    public func read() async throws -> Weight {
        // Poll up to 5 seconds for a stable reading.
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            if let w = latestWeight, w.isStable {
                return w
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw WeightScaleError.readTimeout
    }

    public nonisolated func stream() -> AsyncStream<Weight> {
        AsyncStream { continuation in
            // BUGHUNT-2026-05-18: previously the continuation was appended
            // to `continuations` but never removed — each stream() caller
            // permanently leaked one slot, and `didReceiveCharacteristicData`
            // looped over a growing array on every BLE notification. AsyncStream
            // calls `onTermination` when the consumer cancels or the loop ends;
            // hook it to drop the slot. Use the continuation's object identity
            // for removal (AsyncStream.Continuation is a struct without
            // Equatable, but we wrap it in a class-id token).
            let token = _ContinuationToken(continuation: continuation)
            Task { await self._addContinuation(token) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self._removeContinuation(token) }
            }
        }
    }

    // MARK: - Tare / zero

    /// Tare offset: subtract this from every subsequent reading.
    /// Set by `tare()` to the current stable reading.
    private var tareOffsetGrams: Int = 0

    /// Tare the scale: captures the current stable reading as the zero baseline.
    /// Subsequent readings will have this offset subtracted.
    ///
    /// - Returns: The tare weight that was captured.
    /// - Throws: `WeightScaleError.readTimeout` if no stable reading within 5 s.
    @discardableResult
    public func tare() async throws -> Weight {
        let current = try await read()
        tareOffsetGrams = current.grams
        AppLog.hardware.info("BluetoothWeightScale: tare set to \(current.grams) g")
        return current
    }

    /// Zero the tare offset without requiring a stable reading.
    /// Use when the scale is already empty and known to be at rest.
    public func zeroTare() {
        tareOffsetGrams = 0
        AppLog.hardware.info("BluetoothWeightScale: tare zeroed")
    }

    // MARK: - Characteristic data ingestion

    /// Called by the CoreBluetooth delegate (or tests) to push raw characteristic data.
    public func didReceiveCharacteristicData(_ data: Data) {
        guard let weight = Self.parseWeightMeasurement(data) else {
            AppLog.hardware.warning("BluetoothWeightScale: failed to parse characteristic data (\(data.map { String(format: "%02X", $0) }.joined(separator: " ")))")
            return
        }
        // Apply tare offset: net weight = raw - tare.
        let netGrams = max(0, weight.grams - tareOffsetGrams)
        let netWeight = Weight(grams: netGrams, isStable: weight.isStable)
        latestWeight = netWeight
        for tok in continuationTokens { tok.continuation.yield(netWeight) }
        AppLog.hardware.info("BluetoothWeightScale: raw=\(weight.grams)g tare=\(self.tareOffsetGrams)g net=\(netGrams)g")
    }

    // MARK: - Parsing (internal for testability)

    /// Parse raw bytes from characteristic 0x2A9D.
    /// Returns `nil` when data is too short or contains an unsupported format.
    static func parseWeightMeasurement(_ data: Data) -> Weight? {
        guard data.count >= 3 else { return nil }

        let flags = data[0]
        let unit: MeasurementUnit = (flags & 0x01) == 0 ? .si : .imperial

        // Weight is uint16 little-endian in bytes 1-2.
        let rawValue = UInt16(data[1]) | (UInt16(data[2]) << 8)

        // Bit 0 of flags high nibble in some implementations carries "unstable" hint.
        // The SIG spec does not define a stability bit; we treat zero weight as
        // potentially unstable and non-zero as stable for display purposes.
        let isStable = rawValue > 0

        let grams: Int
        switch unit {
        case .si:
            // Resolution 0.005 kg per LSB → 5 g per LSB.
            grams = Int(rawValue) * 5
        case .imperial:
            // Resolution 0.01 lb per LSB → 1 lb = 453.592 g → 0.01 lb = 4.536 g.
            grams = Int((Double(rawValue) * 0.01 * 453.592).rounded())
        }

        return Weight(grams: grams, isStable: isStable)
    }

    // MARK: - Private helpers

    private func _addContinuation(_ token: _ContinuationToken) {
        continuationTokens.append(token)
        if let w = latestWeight { token.continuation.yield(w) }
    }

    private func _removeContinuation(_ token: _ContinuationToken) {
        continuationTokens.removeAll { $0 === token }
    }
}

/// Class wrapper for AsyncStream.Continuation (a struct) so we can remove
/// a specific subscriber by object identity on stream termination.
private final class _ContinuationToken: @unchecked Sendable {
    let continuation: AsyncStream<BluetoothWeightScale.Weight>.Continuation
    init(continuation: AsyncStream<BluetoothWeightScale.Weight>.Continuation) {
        self.continuation = continuation
    }
}
