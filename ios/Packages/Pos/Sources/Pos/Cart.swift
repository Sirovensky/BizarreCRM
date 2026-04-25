import Foundation
import Observation
import Persistence

/// Immutable snapshot of the customer currently attached to the cart.
/// `id == nil` marks a walk-in / ghost customer — the checkout flow stays
/// viable without a real record (guest checkout is a first-class path).
public struct PosCustomer: Equatable, Sendable {
    public let id: Int64?
    public let displayName: String
    public let email: String?
    public let phone: String?

    public init(id: Int64?, displayName: String, email: String? = nil, phone: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.phone = phone
    }

    /// Sentinel for the ghost / guest path. UI switches on this to show
    /// the walk-in icon + label.
    public var isWalkIn: Bool { id == nil }

    /// Two-letter initials used by avatar circles. Falls back to "W" for
    /// walk-in so the chip never renders as an empty bubble.
    public var initials: String {
        if isWalkIn { return "W" }
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
        let joined = parts.joined()
        return joined.isEmpty ? "?" : joined
    }

    /// Convenience ghost record — every call site gets the same copy so the
    /// UI can render deterministic labels.
    public static let walkIn = PosCustomer(id: nil, displayName: "Walk-in")
}

/// The in-memory POS cart. `@Observable` so SwiftUI views refresh on any
/// mutation and tests can assert on derived totals without plumbing a
/// separate view-model.
///
/// Scaffold-level state plus the attached customer (§16.4) land here.
/// Holds (§16.3), tenders, discounts, and receipts land in later phases.
@MainActor
@Observable
public final class Cart {
    public private(set) var items: [CartItem] = []

    /// Currently attached customer (nil = no customer chosen yet — the
    /// empty-state CTAs surface walk-in / find / create).
    public private(set) var customer: PosCustomer?

    // MARK: - §16.3 — Cart-level adjustments

    /// Fixed cart-level discount in cents. Mutually exclusive with
    /// `cartDiscountPercent`: when the percent is set this is recomputed
    /// lazily; when set directly the percent is cleared.
    public private(set) var cartDiscountCents: Int = 0

    /// Percentage discount applied to the subtotal (e.g. 0.10 = 10%).
    /// `nil` means we're using a fixed-cents discount instead.
    public private(set) var cartDiscountPercent: Double? = nil

    /// Tip in cents. Represents the cashier-entered tip before payment.
    public private(set) var tipCents: Int = 0

    /// Extra fees in cents (delivery, restocking, etc.).
    public private(set) var feesCents: Int = 0

    /// Human-readable label for the fees row (e.g. "Delivery fee").
    /// `nil` when no fee is applied.
    public private(set) var feesLabel: String? = nil

    /// Server-assigned hold id once this cart has been saved as a hold.
    public private(set) var holdId: Int64? = nil

    /// Note stored alongside the hold on the server.
    public private(set) var holdNote: String? = nil

    // MARK: - Applied tenders (§40)
    //
    // Gift cards + store credit aren't payment rails — they're pre-charge
    // reductions of the amount the customer still owes. We attach them to
    // the cart so the totals footer can show `Total − tenders = Remaining`
    // and the Charge CTA can flip to "Complete" once remaining hits zero.
    //
    // Order matters: tenders are appended in the order the cashier applied
    // them so the receipt reconstructs the same sequence.

    /// Tenders already applied to the cart. Each reduces `remainingCents`.
    public private(set) var appliedTenders: [AppliedTender] = []

    // MARK: - Pending payment link (§41)
    //
    // When staff generates a public payment link for the current cart the
    // cashier can no longer Charge at the terminal — the customer will pay
    // via the web page. Holding the link id + token lets the next-sale
    // flow cancel the pending link before starting fresh so we never end
    // up with a zombie "active" row, and lets the POS UI rebuild the share
    // URL without a follow-up GET.

    /// Server id of the payment link currently attached to the cart, or
    /// `nil`. Drives the Charge-disabled state and the post-sale cancel path.
    public private(set) var pendingPaymentLinkId: Int64?

    /// Token of the pending payment link.
    public private(set) var pendingPaymentLinkToken: String?

    // MARK: - §16 Discount engine results

    /// Per-line discount applications written by `DiscountEngine` + `CartViewModel`.
    /// Keyed by `CartItem.id`. Empty until the engine runs for the first time.
    public private(set) var appliedDiscounts: [UUID: [DiscountApplication]] = [:]

    /// Cart-level (`.whole` scope) discount applications.
    public private(set) var cartDiscountApplications: [DiscountApplication] = []

    /// When `true`, at least one applied discount rule requires manager approval
    /// before the cart may proceed to checkout.
    public private(set) var discountRequiresManagerApproval: Bool = false

    // MARK: - §37 Applied coupons

    /// Coupon codes applied to this cart.  At most one coupon per rule is
    /// allowed (the input sheet enforces this at the UX level); the array
    /// permits multiple distinct coupons from different rules.
    public private(set) var appliedCoupons: [CouponCode] = []

    /// Total cents saved from applied coupons.
    public private(set) var couponDiscountCents: Int = 0

    // MARK: - §6 Pricing engine results

    /// Pricing adjustments (BOGO / tiered / bundle) produced by `PricingEngine`.
    public private(set) var pricingAdjustments: [UUID: [PricingAdjustment]] = [:]

    /// Total savings from pricing rules (computed by engine).
    public private(set) var pricingSavingCents: Int = 0

    public init(items: [CartItem] = [], customer: PosCustomer? = nil) {
        self.items = items
        self.customer = customer
    }

    // MARK: - Mutations (always replace, never in-place edit)

    public func add(_ item: CartItem) {
        items = items + [item]
    }

    /// Atomically append multiple lines in a single array replacement.
    /// Used by the bundle resolver so service + children land as one undo unit.
    public func addLines(_ newLines: [CartItem]) {
        guard !newLines.isEmpty else { return }
        items = items + newLines
    }

    /// Remove all lines whose `notes` field equals `tag`.
    /// Returns the number of lines removed.
    /// Used by the bundle remove flow (`Cart+addBundle.swift`).
    @discardableResult
    public func removeLines(withNotesTag tag: String) -> Int {
        let before = items.count
        items = items.filter { $0.notes != tag }
        return before - items.count
    }

    /// Remove a line from the cart. Retained for callsites predating §16.11
    /// that don't need audit logging (e.g. internal state reset, test helpers).
    @available(*, deprecated, message: "Use removeLine(id:reason:managerId:) to emit an audit event.")
    public func remove(id: UUID) {
        items = items.filter { $0.id != id }
    }

    /// §16.11 — Audited line removal.
    ///
    /// Logs a `void_line` or `delete_line` event to `PosAuditLogStore` before
    /// dropping the row from the cart.  The event type is determined by
    /// `managerId`: when a manager approved the action (non-nil), the event is
    /// `void_line`; otherwise it is `delete_line`.
    ///
    /// Errors from the audit store are logged but do NOT block the removal —
    /// the cart mutation always succeeds so the cashier is never stuck.
    ///
    /// - Parameters:
    ///   - id:        The `CartItem.id` to remove.
    ///   - reason:    Free-form reason entered by the cashier.
    ///   - managerId: Manager who approved, or nil for cashier-self-service delete.
    ///   - cashierId: Acting cashier. Defaults to 0 placeholder.
    public func removeLine(id: UUID, reason: String? = nil, managerId: Int64? = nil, cashierId: Int64 = 0) {
        guard let item = items.first(where: { $0.id == id }) else { return }

        let eventType = managerId != nil
            ? PosAuditEntry.EventType.voidLine
            : PosAuditEntry.EventType.deleteLine

        // Capture only Sendable primitives before crossing the Task boundary.
        // [String: Any] is not Sendable in Swift 6 strict mode; we pass the
        // individual values and build the dict inside the actor.
        let lineName        = item.name
        let lineSku         = item.sku
        let lineSubtotal    = item.lineSubtotalCents
        let capturedEvent   = eventType
        let capturedCashier = cashierId
        let capturedManager = managerId
        let capturedReason  = reason

        // Fire-and-forget: audit failure must never block the cashier.
        Task {
            var ctx: [String: Any] = ["lineName": lineName, "originalPriceCents": lineSubtotal]
            if let sku = lineSku { ctx["sku"] = sku }
            try? await PosAuditLogStore.shared.record(
                event: capturedEvent,
                cashierId: capturedCashier,
                managerId: capturedManager,
                amountCents: lineSubtotal,
                reason: capturedReason,
                context: ctx
            )
        }

        items = items.filter { $0.id != id }
    }

    public func update(id: UUID, quantity: Int) {
        guard quantity >= 1 else {
            // Internal path: quantity-to-zero drops the item with no audit event.
            // Suppress the deprecation — this is intentional non-audited removal.
            items = items.filter { $0.id != id }
            return
        }
        items = items.map { row in
            row.id == id ? row.with(quantity: quantity) : row
        }
    }

    public func update(id: UUID, unitPriceCents: Int) {
        let clamped = max(0, unitPriceCents)
        let price = Decimal(clamped) / 100
        items = items.map { row in
            row.id == id ? row.with(unitPrice: price) : row
        }
    }

    public func update(id: UUID, discountCents: Int) {
        items = items.map { row in
            row.id == id ? row.with(discountCents: max(0, discountCents)) : row
        }
    }

    /// Persist the per-line note typed in the iPad inspector pane (or the
    /// iPhone line-edit sheet). Empty / whitespace-only strings collapse to
    /// `nil` so receipts and exports don't print a stray blank "Note:" row.
    public func update(id: UUID, notes: String?) {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        items = items.map { row in
            guard row.id == id else { return row }
            // CartItem.with(notes:) treats nil as "keep current"; we need an
            // explicit clear path, so build the row by hand when stored == nil.
            if stored == nil {
                return CartItem(
                    id: row.id,
                    inventoryItemId: row.inventoryItemId,
                    name: row.name,
                    sku: row.sku,
                    quantity: row.quantity,
                    unitPrice: row.unitPrice,
                    taxRate: row.taxRate,
                    discountCents: row.discountCents,
                    notes: nil
                )
            }
            return row.with(notes: stored)
        }
    }

    /// Drop every line. The attached customer is also cleared — the next
    /// sale starts from a clean slate per §16.4. The pending payment-link
    /// reference is dropped locally; the UI layer is responsible for
    /// deciding whether to call `cancelPaymentLink` before calling `clear()`
    /// (see §41 next-sale flow).
    public func clear() {
        items = []
        customer = nil
        pendingPaymentLinkId = nil
        pendingPaymentLinkToken = nil
        appliedTenders = []
        cartDiscountCents = 0
        cartDiscountPercent = nil
        tipCents = 0
        feesCents = 0
        feesLabel = nil
        holdId = nil
        holdNote = nil
        appliedDiscounts = [:]
        cartDiscountApplications = []
        discountRequiresManagerApproval = false
        appliedCoupons = []
        couponDiscountCents = 0
        pricingAdjustments = [:]
        pricingSavingCents = 0
    }

    // MARK: - §16 Discount engine integration

    /// Write back results from `DiscountEngine.apply(cart:rules:)`.
    public func applyDiscountResult(_ result: DiscountResult) {
        appliedDiscounts = result.lineApplications
        cartDiscountApplications = result.cartApplications
        discountRequiresManagerApproval = result.requiresManagerApproval
        // Merge engine discount into cartDiscountCents so totals footer
        // remains the single source of truth.
        cartDiscountCents = result.totalDiscountCents
        cartDiscountPercent = nil  // engine result takes precedence
    }

    // MARK: - §37 Coupon mutators

    /// Attach a validated coupon to the cart. Replaces any existing coupon
    /// from the same rule (same `ruleId`).
    public func applyCoupon(_ coupon: CouponCode, discountCents: Int) {
        appliedCoupons = appliedCoupons.filter { $0.ruleId != coupon.ruleId } + [coupon]
        couponDiscountCents = appliedCoupons.count > 0
            ? couponDiscountCents + discountCents
            : discountCents
    }

    /// Remove a coupon by its id and reduce the coupon discount accordingly.
    public func removeCoupon(id: String, discountCents: Int) {
        appliedCoupons = appliedCoupons.filter { $0.id != id }
        couponDiscountCents = max(0, couponDiscountCents - discountCents)
    }

    /// Clear all applied coupons.
    public func clearCoupons() {
        appliedCoupons = []
        couponDiscountCents = 0
    }

    // MARK: - §6 Pricing engine integration

    /// Write back results from `PricingEngine.apply(cart:rules:)`.
    public func applyPricingResult(_ result: PricingResult) {
        pricingAdjustments = result.adjustments
        pricingSavingCents = result.totalSavingCents
    }

    // MARK: - §16.3 — Cart-level adjustment mutators

    /// Apply a fixed-cents cart discount. Clears any percentage discount.
    public func setCartDiscount(cents: Int) {
        cartDiscountCents = max(0, cents)
        cartDiscountPercent = nil
    }

    /// Apply a percentage cart discount (e.g. 0.10 for 10%). Recomputes
    /// `cartDiscountCents` against the current subtotal and stores the
    /// percent so future subtotal changes can re-derive the amount.
    public func setCartDiscountPercent(_ percent: Double) {
        let clamped = max(0.0, min(1.0, percent))
        cartDiscountPercent = clamped
        cartDiscountCents = Int((Double(subtotalCents) * clamped).rounded())
    }

    /// Remove any cart-level discount entirely.
    public func clearCartDiscount() {
        cartDiscountCents = 0
        cartDiscountPercent = nil
    }

    /// Set tip as a fixed cent amount.
    public func setTip(cents: Int) {
        tipCents = max(0, cents)
    }

    /// Set tip as a percentage of the current subtotal-after-discount.
    /// E.g. `setTipPercent(0.15)` = 15% tip.
    public func setTipPercent(_ percent: Double) {
        let base = max(0, subtotalCents - effectiveDiscountCents)
        tipCents = Int((Double(base) * max(0.0, percent)).rounded())
    }

    /// Set fees with an optional human label.
    public func setFees(cents: Int, label: String? = nil) {
        feesCents = max(0, cents)
        feesLabel = label
    }

    // MARK: - §16.3 — Hold support

    /// Mark the cart as saved on the server as a hold. Called by the
    /// PosHoldCartSheet after a successful `POST /pos/holds`.
    /// NEVER inherit a pending payment link from a resumed hold.
    public func markHeld(id: Int64, note: String?) {
        holdId = id
        holdNote = note
    }

    // MARK: - Pending payment link (§41)

    /// Mark the cart as waiting on a public payment-link completion. This
    /// disables Charge in the UI — the customer will pay via the web page,
    /// and the POS terminal must not also attempt to capture the same sale.
    public func markPendingPaymentLink(id: Int64, token: String) {
        pendingPaymentLinkId = id
        pendingPaymentLinkToken = token
    }

    /// Drop the pending-link reference without touching anything else on
    /// the cart. Used after a successful webhook-driven paid-status flip,
    /// and by the next-sale flow that cancels the link.
    public func clearPendingPaymentLink() {
        pendingPaymentLinkId = nil
        pendingPaymentLinkToken = nil
    }

    /// True while the cart is waiting on a public-page payment. Drives the
    /// disabled state on the Charge CTA.
    public var hasPendingPaymentLink: Bool { pendingPaymentLinkId != nil }

    // MARK: - Customer (§16.4)

    /// Attach (or swap) the customer on the cart. Last write wins.
    public func attach(customer: PosCustomer) {
        self.customer = customer
    }

    /// Detach the customer without clearing the cart contents.
    public func detachCustomer() {
        customer = nil
    }

    /// `true` once the cashier has made an explicit pick (walk-in counts).
    public var hasCustomer: Bool { customer != nil }

    // MARK: - Applied tenders (§40)

    /// Append `tender` to the applied-tenders list. Zero-amount rows are
    /// dropped so a buggy call site can't smuggle a no-op entry onto the
    /// cart. No dedup — two different gift cards can tender one cart.
    public func apply(tender: AppliedTender) {
        guard tender.amountCents > 0 else { return }
        appliedTenders = appliedTenders + [tender]
    }

    /// Remove a single tender by its client-side id. Silent no-op if the
    /// id is unknown — the caller already saw the row disappear from the
    /// UI, and logging here would be noise.
    public func removeTender(id: UUID) {
        appliedTenders = appliedTenders.filter { $0.id != id }
    }

    /// Drop every applied tender. Used when the cashier backs out of the
    /// charge flow and wants to start the tender choice from scratch.
    public func clearTenders() {
        appliedTenders = []
    }

    /// Sum of applied tenders in cents. Never negative — the mutators
    /// above guarantee each row is positive.
    public var appliedTendersCents: Int {
        appliedTenders.reduce(0) { $0 + $1.amountCents }
    }

    /// Amount the customer still owes after tenders are applied. Clamped
    /// at zero so an over-tendered cart (server would reject) still
    /// renders a sane "Remaining $0.00" row rather than a negative.
    public var remainingCents: Int {
        max(0, totalCents - appliedTendersCents)
    }

    /// `true` once tenders fully cover the cart — drives the Charge →
    /// Complete CTA swap in `PosCartPanel`.
    public var isFullyTendered: Bool {
        !items.isEmpty && remainingCents == 0 && appliedTendersCents > 0
    }

    // MARK: - Totals

    public var subtotalCents: Int {
        items.reduce(0) { $0 + $1.lineSubtotalCents }
    }

    public var taxCents: Int {
        items.reduce(0) { $0 + $1.lineTaxCents }
    }

    /// The actual discount applied — if `cartDiscountPercent` is set we
    /// always re-derive from the live subtotal so it stays correct as items
    /// are added/removed. Clamped to the subtotal so we can't discount below 0.
    public var effectiveDiscountCents: Int {
        if let percent = cartDiscountPercent {
            let derived = Int((Double(subtotalCents) * percent).rounded())
            return min(derived, subtotalCents)
        }
        return min(cartDiscountCents, subtotalCents)
    }

    /// §16.3 — Cart total includes discount, tax, tip, fees, coupon and pricing savings.
    /// `max(0, ...)` guards the discounted-past-zero edge case.
    public var totalCents: Int {
        let allDiscounts = effectiveDiscountCents + couponDiscountCents + pricingSavingCents
        let discounted = max(0, subtotalCents - allDiscounts)
        return discounted + taxCents + tipCents + feesCents
    }

    /// Combined discount in cents from all sources (manual + engine + coupons + pricing).
    public var totalSavingsCents: Int {
        effectiveDiscountCents + couponDiscountCents + pricingSavingCents
    }

    public var isEmpty: Bool { items.isEmpty }

    public var lineCount: Int { items.count }

    public var itemQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
}
