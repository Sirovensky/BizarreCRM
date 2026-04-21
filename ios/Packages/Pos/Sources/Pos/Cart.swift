import Foundation
import Observation

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
/// Holds, tenders, discounts, and receipts land in later phases
/// (§16.3, §16.5, §16.6).
@MainActor
@Observable
public final class Cart {
    public private(set) var items: [CartItem] = []

    /// Currently attached customer (nil = no customer chosen yet — the
    /// empty-state CTAs surface walk-in / find / create).
    public private(set) var customer: PosCustomer?

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

    public init(items: [CartItem] = [], customer: PosCustomer? = nil) {
        self.items = items
        self.customer = customer
    }

    // MARK: - Mutations (always replace, never in-place edit)

    public func add(_ item: CartItem) {
        items = items + [item]
    }

    public func remove(id: UUID) {
        items = items.filter { $0.id != id }
    }

    public func update(id: UUID, quantity: Int) {
        guard quantity >= 1 else {
            remove(id: id)
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

    public var totalCents: Int {
        subtotalCents + taxCents
    }

    public var isEmpty: Bool { items.isEmpty }

    public var lineCount: Int { items.count }

    public var itemQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
}
