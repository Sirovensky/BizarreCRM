import Foundation

// MARK: - WeightScaleError

public enum WeightScaleError: Error, LocalizedError, Sendable {
    case notConnected
    case readTimeout
    case invalidData(String)
    case unsupportedUnit

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Weight scale is not connected. Pair the scale via Settings → Hardware → Bluetooth."
        case .readTimeout:
            return "Weight reading timed out. Check that the scale is powered on and in range."
        case .invalidData(let detail):
            return "Received invalid data from scale: \(detail)"
        case .unsupportedUnit:
            return "The scale is reporting a unit that is not supported."
        }
    }
}

// MARK: - WeightScale Protocol

/// Abstraction over physical and simulated weight scales.
///
/// Concrete implementations:
/// - `BluetoothWeightScale` — BLE Weight Scale Service (0x181D)
/// - `NullWeightScale` — stub for use when no hardware is paired
public protocol WeightScale: Sendable {
    /// Take a single stable reading.
    func read() async throws -> Weight
    /// Stream live readings (useful for animated display chips).
    func stream() -> AsyncStream<Weight>
    /// Zero the tare offset (captures current stable reading as baseline).
    /// Throws `WeightScaleError.readTimeout` if no stable reading within 5 s.
    @discardableResult
    func tare() async throws -> Weight
}

// MARK: - NullWeightScale

/// No-op scale returned when no hardware is paired.
public struct NullWeightScale: WeightScale {
    public init() {}

    public func read() async throws -> Weight {
        throw WeightScaleError.notConnected
    }

    public func stream() -> AsyncStream<Weight> {
        AsyncStream { continuation in continuation.finish() }
    }

    public func tare() async throws -> Weight {
        throw WeightScaleError.notConnected
    }
}
