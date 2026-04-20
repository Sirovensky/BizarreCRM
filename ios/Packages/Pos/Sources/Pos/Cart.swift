import Foundation
import Observation

/// The in-memory POS cart. `@Observable` so SwiftUI views refresh on any
/// mutation and tests can assert on derived totals without plumbing a
/// separate view-model.
///
/// Scaffold-level state only — holds, customers, tenders, discounts, and
/// receipts land in later phases (§16.3, §16.4, §16.6). This class's single
/// job is: items go in, totals come out.
@MainActor
@Observable
public final class Cart {
    public private(set) var items: [CartItem] = []

    public init(items: [CartItem] = []) {
        self.items = items
    }

    // MARK: - Mutations (always replace, never in-place edit)

    /// Append a new row. Same-inventory items do NOT auto-merge at this
    /// scaffold level — cashiers who want that use the `+` button on an
    /// existing row. Keeps the write paths easy to reason about.
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

    public func clear() {
        items = []
    }

    // MARK: - Totals

    /// Sum of all line subtotals (after per-line discounts, before tax).
    public var subtotalCents: Int {
        items.reduce(0) { $0 + $1.lineSubtotalCents }
    }

    /// Sum of all line taxes. Lines with `taxRate == nil` contribute 0 —
    /// they inherit the tenant default in a later phase.
    public var taxCents: Int {
        items.reduce(0) { $0 + $1.lineTaxCents }
    }

    /// Subtotal + tax. Single source of truth for the "Charge" button
    /// label.
    public var totalCents: Int {
        subtotalCents + taxCents
    }

    /// `true` when the cart has no lines. Drives the empty-state chrome in
    /// `PosView`.
    public var isEmpty: Bool { items.isEmpty }

    /// Unique-line count, used by toolbars and accessibility labels.
    public var lineCount: Int { items.count }

    /// Total quantity across all lines — different from `lineCount` when
    /// the cashier bumps `+` on a row.
    public var itemQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
}
