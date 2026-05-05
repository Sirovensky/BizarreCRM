import Foundation

// MARK: - ABTestVariant

/// A single variant in an A/B test campaign.
///
/// `splitPercent` is an integer 1–99 representing this variant's share of traffic.
/// All variants in a test must sum to exactly 100; see `SplitRatioValidator`.
///
/// Client-side only: no server endpoint for A/B variant assignment exists.
/// Variant assignment is performed deterministically by `VariantAssignmentCalculator`.
public struct ABTestVariant: Identifiable, Codable, Equatable, Sendable, Hashable {
    public let id: String
    /// Short display label, e.g. "Variant A" or "Control".
    public var label: String
    /// The message body sent to customers in this variant.
    public var message: String
    /// Percentage of traffic routed to this variant (integer, 1–99).
    public var splitPercent: Int

    public init(id: String = UUID().uuidString, label: String, message: String, splitPercent: Int) {
        self.id = id
        self.label = label
        self.message = message
        self.splitPercent = splitPercent
    }
}

// MARK: - Preset splits

public extension ABTestVariant {
    /// Returns a canonical 50/50 pair (Variant A / Variant B).
    static func fiftyFifty(messageA: String = "", messageB: String = "") -> [ABTestVariant] {
        [
            ABTestVariant(label: "Variant A", message: messageA, splitPercent: 50),
            ABTestVariant(label: "Variant B", message: messageB, splitPercent: 50),
        ]
    }

    /// Returns a canonical 60/40 pair (Variant A / Variant B).
    static func sixtyForty(messageA: String = "", messageB: String = "") -> [ABTestVariant] {
        [
            ABTestVariant(label: "Variant A", message: messageA, splitPercent: 60),
            ABTestVariant(label: "Variant B", message: messageB, splitPercent: 40),
        ]
    }
}
