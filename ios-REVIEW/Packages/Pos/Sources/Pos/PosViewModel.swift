import Foundation
import Observation
import Core
import Networking
import Inventory

// MARK: - PosViewModel
//
// §16.1 Architecture — Provides meta-state that spans POS sessions:
//   1. Permission gating: pos.access role check (PosUserRole).
//   2. Customer-context signals: group discount, tax exemption, loyalty preview.
//   3. Favorites + recently-sold catalog state (persisted locally).
//   4. Repair-services list from /repair-pricing/services.
//   5. Client-side catalog filtering (§16.2 Search filters).
//
// `Cart` remains the single source of truth for in-session money math.
// PosViewModel is injected into PosView alongside Cart so tests can drive
// both independently.

// MARK: - Permission gate (§16.1)

/// Minimal role descriptor passed from the app's session layer.
/// `pos.access` is the gate check; other flags control override capabilities.
///
/// Populated from AppState (which reads /auth/me on login). In Phase 5 this
/// becomes a proper enum matching the server permission matrix; for Phase 5
/// the single bool is sufficient to gate the POS screen.
public struct PosUserRole: Sendable, Equatable {
    /// Whether the current user may access the POS screen at all.
    public let canAccessPos: Bool
    /// Whether the user can override price / discount limits without a manager PIN.
    public let canOverridePrice: Bool
    /// User's display name for the register header subtitle.
    public let displayName: String
    /// Admin contact shown in the "Not enabled" CTA so staff know who to ask.
    public let adminContact: String?

    public init(
        canAccessPos: Bool = false,
        canOverridePrice: Bool = false,
        displayName: String = "",
        adminContact: String? = nil
    ) {
        self.canAccessPos = canAccessPos
        self.canOverridePrice = canOverridePrice
        self.displayName = displayName
        self.adminContact = adminContact
    }

    /// Permissive role for previews / tests where permission gating is not the focus.
    public static let preview = PosUserRole(
        canAccessPos: true,
        canOverridePrice: true,
        displayName: "Preview Staff"
    )

    /// Default when the role has not loaded yet (blocks POS access as a safe fallback).
    public static let loading = PosUserRole(
        canAccessPos: false,
        canOverridePrice: false,
        displayName: ""
    )
}

// MARK: - Customer context signals (§16.4)

/// Derived from the attached customer; drives cart behaviour automatically.
public struct PosCustomerContext: Equatable, Sendable {
    /// Non-nil when the customer is in a group with an automatic discount.
    /// Value 0.10 = 10% off. Applied via `Cart.setCartDiscountPercent`.
    public let groupDiscountPercent: Double?
    /// Human label for the customer group, e.g. "VIP Members". Used in banner.
    public let groupName: String?
    /// When true all line-level tax rows are suppressed; a banner is shown.
    public let isTaxExempt: Bool
    /// Exemption certificate number, shown in the tax-exempt banner when non-nil.
    public let exemptionCertNumber: String?
    /// Points the customer has already accumulated (show in loyalty banner).
    public let loyaltyPointsBalance: Int?
    /// Points earned per dollar spent; drives the earn-preview calculation.
    /// Nil when loyalty is not active for this customer.
    public let loyaltyPointsPerDollar: Double?

    public init(
        groupDiscountPercent: Double? = nil,
        groupName: String? = nil,
        isTaxExempt: Bool = false,
        exemptionCertNumber: String? = nil,
        loyaltyPointsBalance: Int? = nil,
        loyaltyPointsPerDollar: Double? = nil
    ) {
        self.groupDiscountPercent = groupDiscountPercent
        self.groupName = groupName
        self.isTaxExempt = isTaxExempt
        self.exemptionCertNumber = exemptionCertNumber
        self.loyaltyPointsBalance = loyaltyPointsBalance
        self.loyaltyPointsPerDollar = loyaltyPointsPerDollar
    }

    public static let empty = PosCustomerContext()
}

// MARK: - Fixed catalog category tabs (§16.2 Hierarchy)

/// Top chip row: All / Services / Parts / Accessories / Custom.
public enum PosCatalogCategory: String, CaseIterable, Sendable, Identifiable {
    case all          = "All"
    case services     = "Services"
    case parts        = "Parts"
    case accessories  = "Accessories"
    case custom       = "Custom"

    public var id: String { rawValue }

    /// Maps to `InventoryListItem.itemType` for server-side filter.
    /// `nil` = show all item types.
    public var inventoryFilterValue: String? {
        switch self {
        case .all:         return nil
        case .services:    return "service"
        case .parts:       return "part"
        case .accessories: return "accessory"
        case .custom:      return nil   // custom lines are cart-only
        }
    }

    public var systemImage: String {
        switch self {
        case .all:         return "square.grid.2x2"
        case .services:    return "wrench.and.screwdriver"
        case .parts:       return "puzzlepiece"
        case .accessories: return "cable.connector"
        case .custom:      return "plus.rectangle.portrait"
        }
    }
}

// MARK: - Extended search filters (§16.2 Search filters)

/// State for the extended filter sheet ("Filter by…" bottom sheet).
public struct PosCatalogFilter: Equatable, Sendable {
    /// Fixed category tab. Drives primary chip selection + server item_type query.
    public var category: PosCatalogCategory = .all
    /// Show only items that have `inStock > 0`.
    public var inStockOnly: Bool = false
    /// Show only items that carry tax (taxable=1 in inventory). Client-side only.
    public var taxableOnly: Bool = false
    /// Optional price floor in cents.
    public var minPriceCents: Int? = nil
    /// Optional price ceiling in cents.
    public var maxPriceCents: Int? = nil

    public static let empty = PosCatalogFilter()

    /// True when any filter beyond category == .all is active.
    public var hasNonCategoryFilter: Bool {
        inStockOnly || taxableOnly || minPriceCents != nil || maxPriceCents != nil
    }

    /// True when any non-trivial filter is set (used for badge on filter button).
    public var isFiltered: Bool {
        category != .all || hasNonCategoryFilter
    }
}

// MARK: - PosViewModel

@MainActor
@Observable
public final class PosViewModel {

    // MARK: Permission

    /// Resolved from the app session. Drives the §16.1 permission gate.
    public private(set) var userRole: PosUserRole

    // MARK: Customer context (§16.4)

    public private(set) var customerContext: PosCustomerContext = .empty
    public private(set) var isLoadingCustomerContext: Bool = false

    // MARK: Catalog filter (§16.2)

    public var catalogFilter: PosCatalogFilter = .empty

    // MARK: Favorites (§16.2 Favorites)

    public private(set) var favoriteItemIds: Set<Int64> = []

    // MARK: Recently sold (§16.2 Recently sold)

    /// Up to 10 inventory item ids sold most recently on this register.
    /// Populated client-side; server endpoint not yet available.
    public private(set) var recentlySoldIds: [Int64] = []

    // MARK: Repair services (§16.2 Repair services)

    public private(set) var repairServices: [RepairService] = []
    public private(set) var isLoadingRepairServices: Bool = false

    // MARK: Private

    private let api: APIClient?
    @ObservationIgnored private let favoritesKey = "com.bizarrecrm.pos.favoriteItemIds"

    // MARK: Init

    public init(api: APIClient? = nil, userRole: PosUserRole = .preview) {
        self.api = api
        self.userRole = userRole
        loadFavorites()
    }

    // MARK: Customer context loading (§16.4)

    /// Load group discount, tax exemption, and loyalty balance for the attached customer.
    /// Safe to call multiple times — no-ops when customerId is nil.
    public func loadCustomerContext(customerId: Int64?) async {
        guard let customerId, customerId > 0 else {
            customerContext = .empty
            return
        }
        isLoadingCustomerContext = true
        defer { isLoadingCustomerContext = false }

        // Load customer detail and loyalty balance concurrently.
        async let detailTask: CustomerDetail? = {
            do { return try await api?.customer(id: customerId) } catch { return nil }
        }()
        async let loyaltyTask: LoyaltyBalance? = {
            do { return try await api?.getLoyaltyBalance(customerId: customerId) } catch { return nil }
        }()

        let (detail, loyalty) = await (detailTask, loyaltyTask)

        // Tax-exempt heuristic: look for "tax_exempt" tag until the server
        // adds a dedicated column (audit gap §74 item TBD).
        let tags = detail?.tagList ?? []
        let isTaxExempt = tags.contains(where: { $0.lowercased().replacingOccurrences(of: " ", with: "_") == "tax_exempt" })
        let certNumber = tags.first { $0.lowercased().hasPrefix("cert:") }.map {
            String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }

        // Group discount: not in CustomerDetail yet (server gap). Kept as nil
        // until server ships GET /customer-groups/:id with discount_percent.
        let groupDiscount: Double? = nil

        customerContext = PosCustomerContext(
            groupDiscountPercent: groupDiscount,
            groupName: detail?.customerGroupName,
            isTaxExempt: isTaxExempt,
            exemptionCertNumber: certNumber,
            loyaltyPointsBalance: loyalty?.points,
            loyaltyPointsPerDollar: nil  // points/dollar not yet in server API
        )

        AppLog.pos.info(
            "PosVM: customer context loaded — taxExempt=\(isTaxExempt, privacy: .public) loyaltyPoints=\(loyalty?.points ?? 0, privacy: .public)"
        )
    }

    // MARK: Loyalty points preview (§16.4)

    /// Predicted points from this cart. Nil when loyalty is inactive.
    public func loyaltyPointsPreview(cartTotalCents: Int) -> Int? {
        guard let rate = customerContext.loyaltyPointsPerDollar, rate > 0 else { return nil }
        let dollars = Double(max(0, cartTotalCents)) / 100.0
        return max(0, Int((dollars * rate).rounded()))
    }

    // MARK: Tax exemption application (§16.4)

    /// Suppress tax on all cart lines when the customer is tax-exempt.
    /// Returns `true` if any change was made.
    @discardableResult
    public func applyTaxExemptionIfNeeded(to cart: Cart) -> Bool {
        guard customerContext.isTaxExempt else { return false }
        var changed = false
        for item in cart.items where item.taxRate != nil {
            cart.update(id: item.id, taxRate: nil)
            changed = true
        }
        return changed
    }

    // MARK: Group discount application (§16.4)

    /// Auto-apply the customer group discount to the cart.
    /// Returns the percent applied (0…1) or nil when no group discount is set.
    @discardableResult
    public func applyGroupDiscountIfNeeded(to cart: Cart) -> Double? {
        guard let pct = customerContext.groupDiscountPercent, pct > 0 else { return nil }
        cart.setCartDiscountPercent(pct)
        return pct
    }

    // MARK: Member discount application (§16.15)

    /// Auto-apply the membership tier discount to the cart.
    ///
    /// Called at checkout entry (when the tender screen opens) — NOT at cart
    /// time, per the module-placement guard in `MembershipViewModel`.
    ///
    /// - Parameter discountPercent: Tier discount 0–100 from `LoyaltyAccount.discountPercent`.
    /// - Returns: The fraction applied (0…1), or nil when no discount.
    @discardableResult
    public func applyMemberDiscountIfNeeded(to cart: Cart, discountPercent: Int) -> Double? {
        guard discountPercent > 0 else { return nil }
        let fraction = Double(discountPercent) / 100.0
        // Only apply if there is no existing cart-level discount that is larger.
        // This prevents double-discounting when a manual manager override is higher.
        let existingPct = cart.cartDiscountPercent ?? 0.0
        if fraction > existingPct {
            cart.setCartDiscountPercent(fraction)
            AppLog.pos.info(
                "PosVM: member discount \(discountPercent, privacy: .public)% auto-applied"
            )
            return fraction
        }
        return existingPct > 0 ? existingPct : nil
    }

    /// Whether the current cart has an active member who qualifies for member-only products.
    ///
    /// Views use this to gray out member-only tiles when no qualifying member is attached.
    public var hasMemberAttached: Bool {
        (customerContext.loyaltyPointsBalance != nil) &&
        (customerContext.loyaltyPointsBalance ?? 0) >= 0
    }

    // MARK: Favorites (§16.2 Favorites)

    public func toggleFavorite(itemId: Int64) {
        if favoriteItemIds.contains(itemId) {
            favoriteItemIds.remove(itemId)
        } else {
            favoriteItemIds.insert(itemId)
        }
        saveFavorites()
        AppLog.pos.info("PosVM: toggled favorite for item \(itemId, privacy: .private)")
    }

    public func isFavorite(itemId: Int64) -> Bool {
        favoriteItemIds.contains(itemId)
    }

    private func loadFavorites() {
        let stored = UserDefaults.standard.array(forKey: favoritesKey) as? [Int64] ?? []
        favoriteItemIds = Set(stored)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteItemIds), forKey: favoritesKey)
    }

    // MARK: Repair services (§16.2 Repair services)

    /// Load from `/api/v1/repair-pricing/services`. Idempotent — skips if
    /// already loaded. Call when the user taps the Services tab chip.
    public func loadRepairServicesIfNeeded() async {
        guard repairServices.isEmpty, !isLoadingRepairServices else { return }
        guard let api else { return }
        isLoadingRepairServices = true
        defer { isLoadingRepairServices = false }
        do {
            repairServices = try await api.listRepairServices()
            AppLog.pos.info("PosVM: loaded \(self.repairServices.count, privacy: .public) repair services")
        } catch {
            AppLog.pos.error("PosVM: repair services load failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Recently sold (§16.2 Recently sold)

    /// Record item ids from a completed sale so they surface in the
    /// "Recently sold" chip. Maintains a capped list of 10 unique ids.
    public func recordSale(itemIds: [Int64]) {
        // Merge: sold items float to the top, de-duplicated, capped at 10.
        var merged = itemIds
        for id in recentlySoldIds where !merged.contains(id) {
            merged.append(id)
        }
        recentlySoldIds = Array(merged.prefix(10))
    }

    // MARK: Test injection (internal — not part of public API)

    /// Allows unit tests to inject a known `PosCustomerContext` without
    /// going through the full async API round-trip.
    /// Only accessible within the Pos module (no `public` annotation).
    func _injectCustomerContextForTesting(_ ctx: PosCustomerContext) {
        customerContext = ctx
    }

    // MARK: Catalog filtering helpers (§16.2 Search filters)

    /// Apply client-side filters (in-stock, price range) to items already
    /// returned by the server. Category and keyword are applied server-side.
    public func applyClientFilters(to items: [InventoryListItem]) -> [InventoryListItem] {
        var result = items

        if catalogFilter.inStockOnly {
            result = result.filter { ($0.inStock ?? 0) > 0 }
        }

        if let minCents = catalogFilter.minPriceCents {
            result = result.filter { ($0.priceCents ?? 0) >= minCents }
        }
        if let maxCents = catalogFilter.maxPriceCents {
            result = result.filter { ($0.priceCents ?? Int.max) <= maxCents }
        }

        return result
    }

    /// Sort items: favorites float first, then by display name.
    public func sorted(_ items: [InventoryListItem]) -> [InventoryListItem] {
        items.sorted { a, b in
            let af = favoriteItemIds.contains(a.id)
            let bf = favoriteItemIds.contains(b.id)
            if af != bf { return af }
            return a.displayName < b.displayName
        }
    }
}

// MARK: - Cart extension for tax-rate mutation (§16.4 tax exemption helper)

public extension Cart {
    /// Set or clear the per-line tax rate. `nil` removes tax from the line.
    func update(id: UUID, taxRate: Decimal?) {
        items = items.map { row in
            guard row.id == id else { return row }
            return CartItem(
                id: row.id,
                inventoryItemId: row.inventoryItemId,
                name: row.name,
                sku: row.sku,
                quantity: row.quantity,
                unitPrice: row.unitPrice,
                taxRate: taxRate,
                discountCents: row.discountCents,
                notes: row.notes
            )
        }
    }
}
