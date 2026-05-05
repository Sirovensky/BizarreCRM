import Foundation

// MARK: - TipResult

/// Output of `TipCalculator.compute(subtotalCents:preset:roundUp:)`.
///
/// Carries both the raw computed tip and the final applied tip so callers can
/// display either value without re-computing.
public struct TipResult: Equatable, Sendable {
    /// The tip amount before optional round-up, in cents.
    public let rawCents: Int
    /// The final tip amount (== `rawCents` when `roundUp == false`, next
    /// dollar otherwise), in cents.
    public let finalCents: Int
    /// True when the round-up was actually applied (i.e. `rawCents != finalCents`).
    public let wasRoundedUp: Bool

    public init(rawCents: Int, finalCents: Int) {
        self.rawCents = rawCents
        self.finalCents = finalCents
        self.wasRoundedUp = finalCents != rawCents
    }
}

// MARK: - TipCalculator

/// §16 — Pure, stateless tip computation.
///
/// All methods are static so they can be called from tests and view-models
/// without instantiation. The namespace is a caseless `enum` to prevent
/// accidental instantiation.
public enum TipCalculator {

    /// Compute a tip given a subtotal and a preset.
    ///
    /// - Parameters:
    ///   - subtotalCents: The cart subtotal in cents. Values ≤ 0 produce a zero result.
    ///   - preset:        The selected `TipPreset`.
    ///   - roundUp:       When `true`, the final tip is rounded up to the next whole dollar.
    ///                    Applied after the preset calculation, not during it.
    /// - Returns: A `TipResult` with `rawCents` and `finalCents`.
    public static func compute(
        subtotalCents: Int,
        preset: TipPreset,
        roundUp: Bool = false
    ) -> TipResult {
        guard subtotalCents > 0 else {
            return TipResult(rawCents: 0, finalCents: 0)
        }

        let raw = rawTip(subtotalCents: subtotalCents, value: preset.value)
        let final = roundUp ? roundUpToDollar(cents: raw) : raw
        return TipResult(rawCents: raw, finalCents: final)
    }

    /// Compute a tip from an explicit custom-entry cent amount, with optional round-up.
    ///
    /// - Parameters:
    ///   - subtotalCents:  The cart subtotal (only used as a floor guard).
    ///   - customCents:    The cashier-entered custom tip in cents.
    ///   - roundUp:        When `true`, rounds up to the next whole dollar.
    public static func computeCustom(
        subtotalCents: Int,
        customCents: Int,
        roundUp: Bool = false
    ) -> TipResult {
        let raw = max(0, customCents)
        let final = roundUp ? roundUpToDollar(cents: raw) : raw
        return TipResult(rawCents: raw, finalCents: final)
    }

    // MARK: - Private helpers

    private static func rawTip(subtotalCents: Int, value: TipPresetValue) -> Int {
        switch value {
        case .percentage(let fraction):
            // Banker's-style rounding via Decimal to stay consistent with CartMath.
            let decimal = Decimal(subtotalCents) * Decimal(fraction)
            var input = decimal
            var rounded = Decimal()
            NSDecimalRound(&rounded, &input, 0, .bankers)
            return max(0, NSDecimalNumber(decimal: rounded).intValue)

        case .fixedCents(let cents):
            return max(0, cents)
        }
    }

    /// Round `cents` up to the nearest 100-cent boundary (whole dollar).
    /// E.g. 317 → 400, 300 → 300.
    private static func roundUpToDollar(cents: Int) -> Int {
        guard cents > 0 else { return 0 }
        let remainder = cents % 100
        return remainder == 0 ? cents : cents + (100 - remainder)
    }
}
