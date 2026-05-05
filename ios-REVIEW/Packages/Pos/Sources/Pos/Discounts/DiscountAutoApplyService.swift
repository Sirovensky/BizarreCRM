import Foundation

// MARK: - DiscountAutoApplyResult

/// The output returned by `DiscountAutoApplyService.evaluate(...)`.
///
/// Callers write `appliedCounts` into the cart UI and `result` into the
/// pricing pipeline.
public struct DiscountAutoApplyResult: Sendable {
    /// The full discount result (per-line + cart-level applications).
    public let result: DiscountResult
    /// How many distinct rules were auto-applied. Used to populate
    /// the "N discounts applied" banner in the cart.
    public let appliedCount: Int
    /// Whether the banner should be shown (i.e. at least one discount fired).
    public var showBanner: Bool { appliedCount > 0 }
    /// Localised banner text, e.g. "2 discounts applied".
    public var bannerText: String {
        appliedCount == 1 ? "1 discount applied" : "\(appliedCount) discounts applied"
    }

    public static let empty = DiscountAutoApplyResult(result: .empty, appliedCount: 0)
}

// MARK: - DiscountAutoApplyService

/// Wraps `DiscountEngine` with auto-apply semantics.
///
/// Call `evaluate(cart:rules:context:)` on **every cart mutation**.
/// The service re-runs the engine and returns an updated
/// `DiscountAutoApplyResult` whose `bannerText` drives the "N discounts
/// applied" banner.
///
/// ## Usage
/// ```swift
/// let autoApply = DiscountAutoApplyService()
/// // In CartViewModel.applyDiscounts():
/// let autoResult = await autoApply.evaluate(cart: snapshot, rules: tenantRules, context: ctx)
/// self.discountResult   = autoResult.result
/// self.autoApplyBanner  = autoResult.showBanner ? autoResult.bannerText : nil
/// ```
public actor DiscountAutoApplyService {

    private let engine = DiscountEngine()

    public init() {}

    /// Evaluate all rules against the current cart and return a combined result
    /// with the applied-count for the banner.
    ///
    /// - Parameters:
    ///   - cart:    Current cart snapshot.
    ///   - rules:   Full tenant rule list.
    ///   - context: Eligibility context (channel, customer tier, etc.).
    ///   - now:     Reference date; defaults to `Date.now`.
    public func evaluate(
        cart: DiscountCartSnapshot,
        rules: [DiscountRule],
        context: DiscountContext = .init(),
        now: Date = .now
    ) async -> DiscountAutoApplyResult {

        let result = await engine.apply(cart: cart, rules: rules, context: context, now: now)

        // Count distinct rule IDs across line + cart applications.
        var ruleIds = Set<String>()
        result.lineApplications.values.flatMap { $0 }.forEach { ruleIds.insert($0.ruleId) }
        result.cartApplications.forEach { ruleIds.insert($0.ruleId) }

        return DiscountAutoApplyResult(result: result, appliedCount: ruleIds.count)
    }
}
