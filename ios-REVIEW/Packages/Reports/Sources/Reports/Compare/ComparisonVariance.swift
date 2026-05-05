import Foundation

// MARK: - ComparisonVariance
//
// Pure, stateless functions for computing period-over-period % change.
// No network calls, no side effects — all inputs are plain value types.

public enum ComparisonVariance {

    // MARK: - Core computation

    /// Returns the percentage change between `prior` and `current`.
    ///
    /// - Returns: `((current - prior) / prior) * 100`.
    ///   Returns `nil` when `prior` is zero (division by zero is undefined).
    /// - Parameters:
    ///   - current: Value for the period being analysed.
    ///   - prior:   Value for the baseline (comparison) period.
    public static func percentChange(current: Double, prior: Double) -> Double? {
        guard prior != 0 else { return nil }
        return ((current - prior) / abs(prior)) * 100.0
    }

    /// Returns the percentage change expressed as a `VarianceResult`.
    public static func variance(current: Double, prior: Double) -> VarianceResult {
        guard prior != 0 else {
            return VarianceResult(
                pct: nil,
                direction: current > 0 ? .up : (current < 0 ? .down : .flat)
            )
        }
        let pct = ((current - prior) / abs(prior)) * 100.0
        let direction: VarianceDirection
        if pct > 0 { direction = .up }
        else if pct < 0 { direction = .down }
        else { direction = .flat }
        return VarianceResult(pct: pct, direction: direction)
    }

    // MARK: - Series alignment

    /// Aligns two time-series arrays by index and computes per-point % changes.
    ///
    /// Arrays may differ in length; extra trailing points in the longer array
    /// are dropped. Each returned element pairs `(currentValue, priorValue, pct)`.
    /// `pct` is `nil` where `prior == 0`.
    public static func alignedVariance(
        current: [Double],
        prior: [Double]
    ) -> [AlignedPoint] {
        let count = min(current.count, prior.count)
        return (0..<count).map { i in
            AlignedPoint(
                index: i,
                currentValue: current[i],
                priorValue: prior[i],
                pct: percentChange(current: current[i], prior: prior[i])
            )
        }
    }
}

// MARK: - Supporting types

public struct VarianceResult: Sendable, Equatable {
    /// Percentage change (positive = up, negative = down). `nil` when prior == 0.
    public let pct: Double?
    /// Directional classification.
    public let direction: VarianceDirection

    public init(pct: Double?, direction: VarianceDirection) {
        self.pct = pct
        self.direction = direction
    }
}

public enum VarianceDirection: Sendable, Equatable {
    case up, down, flat
}

public struct AlignedPoint: Sendable, Equatable {
    public let index: Int
    public let currentValue: Double
    public let priorValue: Double
    /// `nil` when prior == 0.
    public let pct: Double?

    public init(index: Int, currentValue: Double, priorValue: Double, pct: Double?) {
        self.index = index
        self.currentValue = currentValue
        self.priorValue = priorValue
        self.pct = pct
    }
}
