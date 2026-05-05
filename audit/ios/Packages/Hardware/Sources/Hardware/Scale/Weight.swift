import Foundation

// MARK: - Weight

/// Immutable physical weight value.
/// Internal representation is integer grams to avoid floating-point drift
/// in summation paths (e.g. accumulating tare + item weights).
public struct Weight: Sendable, Hashable {

    // MARK: - Storage

    /// Weight in grams (integer, authoritative).
    public let grams: Int

    /// Indicates whether the scale has stabilised and the reading is reliable.
    public let isStable: Bool

    // MARK: - Init

    public init(grams: Int, isStable: Bool = true) {
        self.grams = grams
        self.isStable = isStable
    }

    // MARK: - Derived units

    /// Weight in ounces (1 gram = 0.035274 oz).
    public var ounces: Double {
        Double(grams) * 0.035_274
    }

    /// Weight in pounds (1 gram = 0.002205 lb).
    public var pounds: Double {
        Double(grams) * 0.002_204_6
    }

    // MARK: - Factory helpers

    /// Create a Weight from ounces (converted to grams, rounded to nearest gram).
    public static func fromOunces(_ oz: Double, isStable: Bool = true) -> Weight {
        Weight(grams: Int((oz / 0.035_274).rounded()), isStable: isStable)
    }

    /// Create a Weight from pounds (converted to grams, rounded to nearest gram).
    public static func fromPounds(_ lb: Double, isStable: Bool = true) -> Weight {
        Weight(grams: Int((lb / 0.002_204_6).rounded()), isStable: isStable)
    }

    /// Zero weight (e.g. after tare).
    public static let zero = Weight(grams: 0, isStable: true)
}

// MARK: - Comparable

extension Weight: Comparable {
    public static func < (lhs: Weight, rhs: Weight) -> Bool {
        lhs.grams < rhs.grams
    }
}

// MARK: - CustomStringConvertible

extension Weight: CustomStringConvertible {
    public var description: String {
        let stableTag = isStable ? "" : " (unstable)"
        if grams >= 1000 {
            return String(format: "%.3f kg\(stableTag)", Double(grams) / 1000.0)
        } else {
            return "\(grams) g\(stableTag)"
        }
    }
}
