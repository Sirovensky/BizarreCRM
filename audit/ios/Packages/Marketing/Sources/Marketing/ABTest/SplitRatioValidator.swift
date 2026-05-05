import Foundation

// MARK: - SplitRatioValidator

/// Validates that a list of `ABTestVariant` split percentages satisfy the invariants
/// required before a campaign can be saved or launched.
///
/// Rules enforced:
/// - At least 2 variants.
/// - Every `splitPercent` is in the range 1…99.
/// - All `splitPercent` values sum to exactly 100.
public enum SplitRatioValidator {

    public enum ValidationError: LocalizedError, Equatable {
        case tooFewVariants(count: Int)
        case percentOutOfRange(label: String, value: Int)
        case sumNotOneHundred(actual: Int)

        public var errorDescription: String? {
            switch self {
            case .tooFewVariants(let n):
                return "At least 2 variants are required (got \(n))."
            case .percentOutOfRange(let label, let value):
                return "\(label) has an invalid split of \(value)% — must be between 1 and 99."
            case .sumNotOneHundred(let actual):
                return "Split percentages must sum to 100 (currently \(actual)%); adjust the values and try again."
            }
        }
    }

    /// Validates `variants` and returns a `ValidationError` if any rule is violated, or `nil` when valid.
    public static func validate(_ variants: [ABTestVariant]) -> ValidationError? {
        guard variants.count >= 2 else {
            return .tooFewVariants(count: variants.count)
        }
        for variant in variants {
            guard (1...99).contains(variant.splitPercent) else {
                return .percentOutOfRange(label: variant.label, value: variant.splitPercent)
            }
        }
        let total = variants.reduce(0) { $0 + $1.splitPercent }
        guard total == 100 else {
            return .sumNotOneHundred(actual: total)
        }
        return nil
    }

    /// Returns `true` when the variants are valid (percentages sum to 100, each in 1…99, at least 2).
    public static func isValid(_ variants: [ABTestVariant]) -> Bool {
        validate(variants) == nil
    }

    /// The current total of all split percents; useful for live UI feedback.
    public static func total(_ variants: [ABTestVariant]) -> Int {
        variants.reduce(0) { $0 + $1.splitPercent }
    }
}
