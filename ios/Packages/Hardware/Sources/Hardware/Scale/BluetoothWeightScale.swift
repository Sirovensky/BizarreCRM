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
    private var continuations: [AsyncStream<Weight>.Continuation] = []

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
            Task { await self._addContinuation(continuation) }
        }
    }

    // MARK: - Characteristic data ingestion

    /// Called by the CoreBluetooth delegate (or tests) to push raw characteristic data.
    public func didReceiveCharacteristicData(_ data: Data) {
        guard let weight = Self.parseWeightMeasurement(data) else {
            AppLog.hardware.warning("BluetoothWeightScale: failed to parse characteristic data (\(data.map { String(format: "%02X", $0) }.joined(separator: " ")))")
            return
        }
        latestWeight = weight
        for cont in continuations { cont.yield(weight) }
        AppLog.hardware.info("BluetoothWeightScale: \(weight)")
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

    private func _addContinuation(_ continuation: AsyncStream<Weight>.Continuation) {
        continuations.append(continuation)
        if let w = latestWeight { continuation.yield(w) }
    }
}
