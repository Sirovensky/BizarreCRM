import Foundation
import CryptoKit

// MARK: - VariantAssignmentCalculator

/// Assigns a customer to an A/B test variant deterministically using a SHA-256 hash
/// of their `customerID`.
///
/// Algorithm:
/// 1. Compute SHA-256(customerID + experimentID) → 32 bytes.
/// 2. Read the first 4 bytes as a big-endian `UInt32`.
/// 3. Convert to a percentile in [0, 100) via modulo 100.
/// 4. Walk the variant list in order, accumulating split percents; assign to the
///    first variant whose cumulative bucket covers the percentile.
///
/// **No server endpoint required.** The server has no `/campaigns/:id/variant` route
/// (confirmed via grep of `packages/server/src/routes/campaigns.routes.ts`).
/// If the server adds a variant-assignment endpoint in the future, this calculator
/// should be replaced with a network call and the blocker below resolved.
///
/// BLOCKER: Server-side A/B assignment analytics (which variant each recipient
/// actually received) cannot be recorded without a server endpoint. Conversion
/// tracking per variant is unavailable until the server exposes
/// `POST /campaigns/:id/variant-assignment` or similar.
public enum VariantAssignmentCalculator {

    /// Assigns `customerID` to a variant for the given `experimentID`.
    ///
    /// - Parameters:
    ///   - customerID: Stable customer identifier (e.g. database UUID string).
    ///   - experimentID: Stable experiment identifier (e.g. campaign ID).
    ///   - variants: Ordered, valid variant list. Must pass `SplitRatioValidator.isValid`.
    /// - Returns: The assigned `ABTestVariant`, or `nil` when `variants` is empty
    ///   or percentages are invalid.
    public static func assign(
        customerID: String,
        experimentID: String,
        variants: [ABTestVariant]
    ) -> ABTestVariant? {
        guard SplitRatioValidator.isValid(variants) else { return nil }
        let percentile = hashPercentile(customerID: customerID, experimentID: experimentID)
        return variant(atPercentile: percentile, in: variants)
    }

    // MARK: - Internal helpers (package-internal for testability)

    /// Returns an integer in [0, 100) derived from SHA-256(customerID + "|" + experimentID).
    static func hashPercentile(customerID: String, experimentID: String) -> Int {
        let input = "\(customerID)|\(experimentID)"
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        // Read first 4 bytes as big-endian UInt32 then take mod 100.
        let bytes = Array(digest)
        let value = (UInt32(bytes[0]) << 24)
                  | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) <<  8)
                  | UInt32(bytes[3])
        return Int(value % 100)
    }

    /// Walks `variants` in order, assigning to the first variant whose cumulative
    /// bucket covers `percentile` (0-indexed, range [0, 100)).
    static func variant(atPercentile percentile: Int, in variants: [ABTestVariant]) -> ABTestVariant? {
        var cumulative = 0
        for variant in variants {
            cumulative += variant.splitPercent
            if percentile < cumulative {
                return variant
            }
        }
        // Fallback: floating-point imprecision guard — return last variant.
        return variants.last
    }
}
