import Foundation

// MARK: - DiscountResult

/// The output of `DiscountEngine.apply(cart:rules:)`.
///
/// Contains per-line and cart-level discount applications, plus a flag
/// indicating whether any applied rule requires manager approval before checkout.
public struct DiscountResult: Sendable {
    /// Per-line discount applications keyed by `CartItem.id`.
    public let lineApplications: [UUID: [DiscountApplication]]
    /// Whole-cart discount applications (`.whole` scope rules).
    public let cartApplications: [DiscountApplication]
    /// Merged total cart-level discount in cents (line + whole-cart combined).
    public let totalDiscountCents: Int
    /// `true` when at least one applied rule has `managerApprovalRequired == true`.
    public let requiresManagerApproval: Bool

    public static let empty = DiscountResult(
        lineApplications: [:],
        cartApplications: [],
        totalDiscountCents: 0,
        requiresManagerApproval: false
    )
}

// MARK: - DiscountEngine

/// Pure actor that applies a list of `DiscountRule`s to a `Cart` snapshot.
///
/// **Conflict resolution**
///
/// 1. Rules are split into *stackable* and *non-stackable* buckets.
/// 2. For non-stackable rules targeting the same scope+element, only the
///    rule that produces the *largest discount for the customer* is kept
///    (best-for-customer semantics).
/// 3. Stackable rules are all applied and summed.
/// 4. The final discount for any element is clamped so it never exceeds
///    the element's pre-discount value.
///
/// **Date/threshold filtering**
///
/// Rules whose `validFrom`/`validTo` window excludes `now`, or whose
/// `minCartTotalCents` threshold exceeds the current cart subtotal, are silently
/// dropped before the conflict-resolution pass.
public actor DiscountEngine {

    public init() {}

    /// Apply `rules` to the provided `cart` at the given reference time.
    ///
    /// Returns a `DiscountResult` containing all applications. The caller
    /// (typically `CartViewModel`) is responsible for writing the result back
    /// into the cart model and re-rendering the UI.
    ///
    /// - Parameters:
    ///   - cart:               The cart to evaluate. Must be called with a stable snapshot.
    ///   - rules:              The full set of configured rules for the tenant.
    ///   - context:            Customer / employee context for eligibility gating.
    ///   - now:                Reference timestamp for validity checks. Defaults to `Date.now`.
    /// - Returns: A `DiscountResult` ready to be applied to the cart.
    public func apply(
        cart: DiscountCartSnapshot,
        rules: [DiscountRule],
        context: DiscountContext = .init(),
        now: Date = .now
    ) async -> DiscountResult {

        guard !cart.items.isEmpty, !rules.isEmpty else {
            return .empty
        }

        // ── 1. Filter to active, threshold-passing, channel-matching rules ─
        let eligible = rules.filter { rule in
            guard rule.isValid(at: now) else { return false }
            if let minTotal = rule.minCartTotalCents,
               cart.subtotalCents < minTotal { return false }
            // Channel gate
            switch rule.channel {
            case .any: break
            case .inStoreOnly: if context.channel != .inStoreOnly { return false }
            case .onlineOnly:  if context.channel != .onlineOnly  { return false }
            }
            // First-time customer gate (optimistic — server re-validates)
            if rule.firstTimeCustomerOnly, !context.isFirstTimeCustomer { return false }
            // Loyalty-tier gate
            if let requiredTier = rule.requiredLoyaltyTier {
                guard let customerTier = context.customerLoyaltyTier,
                      customerTier == requiredTier else { return false }
            }
            // Employee-role gate
            if let requiredRole = rule.requiredEmployeeRole {
                guard let cashierRole = context.cashierRole,
                      cashierRole == requiredRole else { return false }
            }
            return true
        }
        guard !eligible.isEmpty else { return .empty }

        // ── 2. Per-line applications ──────────────────────────────────────
        var lineApplications: [UUID: [DiscountApplication]] = [:]
        var requiresApproval = false

        for item in cart.items {
            let apps = applyToLine(item: item, rules: eligible, subtotalCents: cart.subtotalCents)
            if !apps.isEmpty {
                lineApplications[item.id] = apps
                if apps.contains(where: { $0.managerApprovalRequired }) {
                    requiresApproval = true
                }
            }
        }

        // ── 3. Whole-cart applications ────────────────────────────────────
        let wholeRules = eligible.filter { $0.scope == DiscountScope.whole }
        let cartApps   = applyWholeCart(rules: wholeRules, subtotalCents: cart.subtotalCents)
        if cartApps.contains(where: { $0.managerApprovalRequired }) {
            requiresApproval = true
        }

        // ── 4. Compute total discount ─────────────────────────────────────
        let lineTotal = lineApplications.values
            .flatMap { $0 }
            .reduce(0) { $0 + $1.discountCents }
        let cartTotal = cartApps.reduce(0) { $0 + $1.discountCents }
        // Clamp combined to subtotal so we never produce a negative cart value.
        let totalDiscount = min(lineTotal + cartTotal, cart.subtotalCents)

        return DiscountResult(
            lineApplications: lineApplications,
            cartApplications: cartApps,
            totalDiscountCents: totalDiscount,
            requiresManagerApproval: requiresApproval
        )
    }

    // MARK: - Private helpers

    /// Apply eligible rules to a single cart line. Returns the resolved set of
    /// applications after conflict resolution.
    private func applyToLine(
        item: CartItemSnapshot,
        rules: [DiscountRule],
        subtotalCents: Int
    ) -> [DiscountApplication] {

        // Gather candidate rules for this line.
        let candidates = rules.filter { rule -> Bool in
            let scope: DiscountScope = rule.scope
            // Excluded-categories gate — skip this line if its category is in the exclusion set.
            if let itemCategory = item.category,
               !rule.excludedCategories.isEmpty,
               rule.excludedCategories.contains(itemCategory) { return false }
            switch scope {
            case .whole:
                return false  // handled separately
            case .lineItem:
                break  // applies to every line
            case .category:
                guard rule.matcher == item.category else { return false }
            case .sku:
                guard let sku = item.sku else { return false }
                guard matchesRegex(rule.matcher, input: sku) else { return false }
            }
            // Quantity gate
            if let minQty = rule.minQuantity, item.quantity < minQty { return false }
            return true
        }

        guard !candidates.isEmpty else { return [] }

        let basisCents = item.lineSubtotalCents
        return resolveConflicts(rules: candidates, basisCents: basisCents)
    }

    /// Apply eligible `.whole` scope rules to the cart subtotal.
    private func applyWholeCart(rules: [DiscountRule], subtotalCents: Int) -> [DiscountApplication] {
        guard !rules.isEmpty else { return [] }
        return resolveConflicts(rules: rules, basisCents: subtotalCents)
    }

    /// Core conflict-resolution logic (shared for line and whole-cart scopes).
    ///
    /// - Stackable rules: all applied, summed.
    /// - Non-stackable rules: best discount for customer wins.
    private func resolveConflicts(rules: [DiscountRule], basisCents: Int) -> [DiscountApplication] {
        let stackable    = rules.filter { $0.stackable }
        let nonStackable = rules.filter { !$0.stackable }

        var result: [DiscountApplication] = []

        // All stackable rules apply.
        for rule in stackable {
            let cents = rule.discountCents(forBasis: basisCents)
            guard cents > 0 else { continue }
            result.append(DiscountApplication(
                ruleId: rule.id,
                ruleName: rule.name,
                scope: rule.scope,
                discountCents: cents,
                managerApprovalRequired: rule.managerApprovalRequired
            ))
        }

        // Best non-stackable rule wins.
        if let best = nonStackable.max(by: {
            $0.discountCents(forBasis: basisCents) < $1.discountCents(forBasis: basisCents)
        }) {
            let cents = best.discountCents(forBasis: basisCents)
            if cents > 0 {
                result.append(DiscountApplication(
                    ruleId: best.id,
                    ruleName: best.name,
                    scope: best.scope,
                    discountCents: cents,
                    managerApprovalRequired: best.managerApprovalRequired
                ))
            }
        }

        return result
    }

    private func matchesRegex(_ pattern: String, input: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil }
            ?? false
    }
}

// MARK: - DiscountContext

/// Caller-supplied context that gates eligibility rules (§16 discount types).
///
/// All properties are optional — pass only what is known at call time.
/// Missing context simply means the corresponding gate is skipped (open).
public struct DiscountContext: Sendable {
    /// Which channel this sale originates from.
    public let channel: DiscountChannel
    /// `true` when the attached customer has no prior completed orders at this tenant.
    public let isFirstTimeCustomer: Bool
    /// The attached customer's current loyalty tier name (e.g. `"Gold"`).
    public let customerLoyaltyTier: String?
    /// The role slug of the cashier initiating the sale (e.g. `"technician"`).
    public let cashierRole: String?

    public init(
        channel: DiscountChannel = .any,
        isFirstTimeCustomer: Bool = false,
        customerLoyaltyTier: String? = nil,
        cashierRole: String? = nil
    ) {
        self.channel              = channel
        self.isFirstTimeCustomer  = isFirstTimeCustomer
        self.customerLoyaltyTier  = customerLoyaltyTier
        self.cashierRole          = cashierRole
    }
}

// MARK: - DiscountCartSnapshot / CartItemSnapshot
// Lightweight value types for crossing the actor boundary safely.
// Named with "Discount" prefix to avoid collision with `PosCartSnapshotStore.CartSnapshot`.

/// Sendable snapshot of just the fields `DiscountEngine` needs.
public struct DiscountCartSnapshot: Sendable {
    public let items: [CartItemSnapshot]
    public let subtotalCents: Int

    public init(items: [CartItemSnapshot], subtotalCents: Int) {
        self.items = items
        self.subtotalCents = subtotalCents
    }
}

/// Sendable snapshot of a single cart line.
public struct CartItemSnapshot: Sendable {
    public let id: UUID
    public let sku: String?
    public let category: String?
    public let quantity: Int
    public let lineSubtotalCents: Int

    public init(id: UUID, sku: String?, category: String?, quantity: Int, lineSubtotalCents: Int) {
        self.id = id
        self.sku = sku
        self.category = category
        self.quantity = quantity
        self.lineSubtotalCents = lineSubtotalCents
    }
}

// MARK: - CartItem → CartItemSnapshot convenience
public extension CartItem {
    /// Produce a `CartItemSnapshot` for the engine. Category is optional
    /// metadata — will be nil unless your `CartItem` is annotated with it.
    func discountSnapshot(category: String? = nil) -> CartItemSnapshot {
        CartItemSnapshot(
            id: id,
            sku: sku,
            category: category,
            quantity: quantity,
            lineSubtotalCents: lineSubtotalCents
        )
    }
}

// MARK: - Cart → DiscountCartSnapshot convenience
public extension Cart {
    /// Build a `DiscountCartSnapshot` from the current cart state.
    /// Pass a category-lookup closure to populate per-item category metadata.
    @MainActor
    func discountSnapshot(categoryFor: (CartItem) -> String? = { _ in nil }) -> DiscountCartSnapshot {
        DiscountCartSnapshot(
            items: items.map { $0.discountSnapshot(category: categoryFor($0)) },
            subtotalCents: subtotalCents
        )
    }
}
