import Foundation

// MARK: - PricingAdjustment

/// A pricing adjustment applied to a single cart line by the `PricingEngine`.
///
/// Stored on `PricingResult` and surfaced in the cart UI as "adjusted price" badges.
public struct PricingAdjustment: Sendable, Hashable {
    /// The rule that produced this adjustment.
    public let ruleId: String
    public let ruleName: String
    public let type: PricingRuleType
    /// For BOGO / bundle rules: how many free units were awarded.
    public let freeUnitsCents: Int
    /// New per-unit price in cents after tiered/segment adjustment (nil = unchanged).
    public let newUnitPriceCents: Int?
    /// Net saving in cents for this line due to this adjustment.
    public let savingCents: Int

    public init(
        ruleId: String,
        ruleName: String,
        type: PricingRuleType,
        freeUnitsCents: Int = 0,
        newUnitPriceCents: Int? = nil,
        savingCents: Int
    ) {
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.type = type
        self.freeUnitsCents = freeUnitsCents
        self.newUnitPriceCents = newUnitPriceCents
        self.savingCents = savingCents
    }
}

// MARK: - PricingResult

/// The output of `PricingEngine.apply(cart:rules:)`.
///
/// Call sites use `effectiveLinePriceCents(for:)` to get the adjusted per-line
/// total to pass to the totals footer and server sale payload.
public struct PricingResult: Sendable {
    /// Per-line adjustments keyed by `CartItem.id`.
    public let adjustments: [UUID: [PricingAdjustment]]
    /// Total saving in cents from all pricing rules.
    public let totalSavingCents: Int

    public static let empty = PricingResult(adjustments: [:], totalSavingCents: 0)

    /// Effective price in cents for a line after all adjustments.
    ///
    /// If multiple adjustments target the same line, the **minimum** resulting
    /// price wins (best for customer). Returns `nil` if no adjustment applies
    /// (caller should use the un-modified `CartItem.lineSubtotalCents`).
    public func effectiveLinePriceCents(for itemId: UUID, originalCents: Int) -> Int? {
        guard let apps = adjustments[itemId], !apps.isEmpty else { return nil }
        let adjusted = apps.compactMap { $0.newUnitPriceCents }
        guard !adjusted.isEmpty else { return nil }
        return adjusted.min()
    }
}

// MARK: - PricingEngine

/// Pure actor that applies a list of `PricingRule`s to a `CartSnapshot` before
/// the `DiscountEngine` runs.
///
/// ## Rule application order
/// 1. Filter to valid, enabled rules for the current date.
/// 2. For each cart line, find all matching rules.
/// 3. Apply:
///    - **bulkBundle**: if the line quantity ≥ `bundleQuantity`, compute
///      the per-unit effective price from the bundle total.
///    - **bogo**: for every `triggerQuantity` units, the next `freeQuantity`
///      units are priced at $0.  Implemented as a total-line savings delta.
///    - **tieredVolume**: look up the active tier for the line quantity;
///      compute the new unit price.
///    - **segmentPrice**: apply a fixed percent discount for matching segment
///      customers (requires the customer segment to be passed).
/// 4. Multiple rules on the same line: best for customer (lowest resulting price).
public actor PricingEngine {

    public init() {}

    /// Apply `rules` to the given `cart`, optionally filtered by `customerSegment`
    /// and `locationSlug`.
    ///
    /// - Parameters:
    ///   - cart:            Cart snapshot to evaluate.
    ///   - rules:           Full tenant rule list.
    ///   - customerSegment: Current customer's segment name (or nil for walk-in).
    ///   - locationSlug:    Current POS location slug (or nil = no location filtering).
    ///   - now:             Reference date for validity checks.
    /// - Returns: `PricingResult` ready to be stored on the cart.
    public func apply(
        cart: DiscountCartSnapshot,
        rules: [PricingRule],
        customerSegment: String? = nil,
        locationSlug: String? = nil,
        now: Date = .now
    ) async -> PricingResult {

        guard !cart.items.isEmpty, !rules.isEmpty else { return .empty }

        // Sort by priority ascending (lower = first match wins per §16 conflict resolution).
        let eligible = rules
            .filter { rule in
                guard rule.isValid(at: now) else { return false }
                // Promotion window: must also be admin-enabled.
                if rule.type == .promotionWindow { return rule.promotionActive }
                return true
            }
            .sorted { $0.priority < $1.priority }
        guard !eligible.isEmpty else { return .empty }

        var allAdjustments: [UUID: [PricingAdjustment]] = [:]
        var totalSaving = 0

        for item in cart.items {
            let matching = eligible.filter {
                matches(rule: $0, item: item, segment: customerSegment, locationSlug: locationSlug)
            }
            guard !matching.isEmpty else { continue }

            var lineAdj: [PricingAdjustment] = []
            for rule in matching {
                if let adj = adjustment(for: rule, item: item) {
                    lineAdj.append(adj)
                    totalSaving += adj.savingCents
                }
            }
            if !lineAdj.isEmpty {
                allAdjustments[item.id] = lineAdj
            }
        }

        return PricingResult(adjustments: allAdjustments, totalSavingCents: max(0, totalSaving))
    }

    // MARK: - Private: matching

    private func matches(
        rule: PricingRule,
        item: CartItemSnapshot,
        segment: String?,
        locationSlug: String?
    ) -> Bool {
        // Segment rules only fire when customer segment matches.
        if rule.type == .segmentPrice {
            guard let seg = segment, let rSeg = rule.targetSegment, seg == rSeg else {
                return false
            }
        }
        // Location rules only fire when the POS location matches.
        if rule.type == .locationOverride {
            if let rLoc = rule.targetLocationSlug, !rLoc.isEmpty {
                guard let loc = locationSlug, loc == rLoc else { return false }
            }
        }
        // SKU match
        if let sku = rule.targetSku, !sku.isEmpty {
            return item.sku == sku
        }
        // Category match
        if let cat = rule.targetCategory, !cat.isEmpty {
            return item.category == cat
        }
        // No specific target → applies to all items (e.g. tiered volume on entire catalog)
        return true
    }

    // MARK: - Private: per-rule adjustment computation

    private func adjustment(for rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        switch rule.type {

        case .bulkBundle:
            return bulkBundleAdjustment(rule: rule, item: item)

        case .bogo:
            return bogoAdjustment(rule: rule, item: item)

        case .tieredVolume:
            return tieredVolumeAdjustment(rule: rule, item: item)

        case .segmentPrice:
            return segmentPriceAdjustment(rule: rule, item: item)

        case .locationOverride:
            return locationOverrideAdjustment(rule: rule, item: item)

        case .promotionWindow:
            return promotionWindowAdjustment(rule: rule, item: item)
        }
    }

    // MARK: bulk bundle

    private func bulkBundleAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let bundleQty = rule.bundleQuantity, bundleQty > 0,
              let bundleTotal = rule.bundlePriceCents,
              item.quantity >= bundleQty else { return nil }

        // How many complete bundles?
        let bundleCount = item.quantity / bundleQty
        let remainder   = item.quantity % bundleQty

        // Per-unit effective price within a bundle.
        let bundleUnitCents = bundleTotal / bundleQty
        let bundledTotal    = bundleCount * bundleQty * bundleUnitCents
        let remainTotal     = remainder * item.unitPriceCentsApprox
        let newTotal        = bundledTotal + remainTotal
        let saving          = max(0, item.lineSubtotalCents - newTotal)

        guard saving > 0 else { return nil }

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.name,
            type: .bulkBundle,
            newUnitPriceCents: bundleUnitCents,
            savingCents: saving
        )
    }

    // MARK: BOGO

    private func bogoAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let triggerQty = rule.triggerQuantity, triggerQty > 0,
              let freeQty    = rule.freeQuantity,    freeQty > 0 else { return nil }

        let cycleSize  = triggerQty + freeQty
        let freeSets   = item.quantity / cycleSize
        let freeUnits  = freeSets * freeQty
        guard freeUnits > 0 else { return nil }

        let freeValueCents = freeUnits * item.unitPriceCentsApprox

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.name,
            type: .bogo,
            freeUnitsCents: freeValueCents,
            savingCents: freeValueCents
        )
    }

    // MARK: Tiered volume

    private func tieredVolumeAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let tiers = rule.tiers, !tiers.isEmpty else { return nil }

        // Find the active tier for the current quantity (sorted ascending).
        let sorted = tiers.sorted { $0.minQty < $1.minQty }
        guard let tier = sorted.last(where: { $0.matches(qty: item.quantity) }) else { return nil }

        let newTotal = tier.unitPriceCents * item.quantity
        let saving   = max(0, item.lineSubtotalCents - newTotal)
        guard saving > 0 else { return nil }

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.name,
            type: .tieredVolume,
            newUnitPriceCents: tier.unitPriceCents,
            savingCents: saving
        )
    }

    // MARK: Segment price

    private func segmentPriceAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let pct = rule.segmentDiscountPercent, pct > 0 else { return nil }

        let saving = Int((Double(item.lineSubtotalCents) * pct).rounded())
        guard saving > 0 else { return nil }

        let newUnitCents = max(0, item.unitPriceCentsApprox - Int((Double(item.unitPriceCentsApprox) * pct).rounded()))

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.name,
            type: .segmentPrice,
            newUnitPriceCents: newUnitCents,
            savingCents: saving
        )
    }

    // MARK: Location override

    /// Applies a flat percent discount for a specific store location.
    private func locationOverrideAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let pct = rule.locationDiscountPercent, pct > 0 else { return nil }

        let saving = Int((Double(item.lineSubtotalCents) * pct).rounded())
        guard saving > 0 else { return nil }

        let newUnitCents = max(0, item.unitPriceCentsApprox - Int((Double(item.unitPriceCentsApprox) * pct).rounded()))

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.name,
            type: .locationOverride,
            newUnitPriceCents: newUnitCents,
            savingCents: saving
        )
    }

    // MARK: Promotion window (flash sale)

    /// Applies the flash-sale percent discount when the promotion is live.
    private func promotionWindowAdjustment(rule: PricingRule, item: CartItemSnapshot) -> PricingAdjustment? {
        guard let pct = rule.promotionDiscountPercent, pct > 0 else { return nil }

        let saving = Int((Double(item.lineSubtotalCents) * pct).rounded())
        guard saving > 0 else { return nil }

        let newUnitCents = max(0, item.unitPriceCentsApprox - Int((Double(item.unitPriceCentsApprox) * pct).rounded()))

        return PricingAdjustment(
            ruleId: rule.id,
            ruleName: rule.promotionLabel ?? rule.name,
            type: .promotionWindow,
            newUnitPriceCents: newUnitCents,
            savingCents: saving
        )
    }
}

// MARK: - CartItemSnapshot extension

extension CartItemSnapshot {
    /// Approximate per-unit price in cents derived from the line subtotal.
    /// Used by the engine when the exact unit price is unavailable in the snapshot.
    var unitPriceCentsApprox: Int {
        guard quantity > 0 else { return 0 }
        return lineSubtotalCents / quantity
    }
}
