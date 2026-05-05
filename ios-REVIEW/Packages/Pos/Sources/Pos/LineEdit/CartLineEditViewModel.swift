/// CartLineEditViewModel.swift — §16.22
///
/// Pure in-memory VM for the cart line edit bottom sheet.
/// No network calls until the cart submits (cart is client-authoritative).
///
/// Discount modes: 5% / 10% / fixed-$ / custom.
/// Note: optional, printed on receipt. Up to 500 chars.
/// Remove: triggers audit log in Cart; requires manager PIN when
/// `PosAuditLogStore.deleteLineRequiresPin` is true (gated in parent).

import Foundation
import Observation

// MARK: - Discount mode

public enum CartLineDiscountMode: CaseIterable, Sendable, Equatable {
    case none
    case percent5
    case percent10
    case fixedCustom

    public var label: String {
        switch self {
        case .none:       return "None"
        case .percent5:   return "5%"
        case .percent10:  return "10%"
        case .fixedCustom: return "$ Custom"
        }
    }
}

// MARK: - CartLineEditViewModel

/// §16.22 — In-memory VM for cart line edit sheet.
@MainActor
@Observable
public final class CartLineEditViewModel {

    // MARK: - Editable state

    public var qty: Int
    public var discountMode: CartLineDiscountMode
    /// Applies when discountMode == .fixedCustom; in cents.
    public var customDiscountCents: Int = 0
    public var note: String

    // MARK: - Read-only from line

    public let lineId: UUID
    public let itemName: String
    public let unitPriceCents: Int
    public let maxQty: Int = 999
    public let noteMaxLength: Int = 500

    // MARK: - Derived

    public var derivedDiscountCents: Int {
        switch discountMode {
        case .none:        return 0
        case .percent5:    return Int(Double(unitPriceCents * qty) * 0.05)
        case .percent10:   return Int(Double(unitPriceCents * qty) * 0.10)
        case .fixedCustom: return min(customDiscountCents, unitPriceCents * qty)
        }
    }

    public var lineTotalCents: Int {
        max(0, unitPriceCents * qty - derivedDiscountCents)
    }

    public var isNoteOverLimit: Bool { note.count > noteMaxLength }
    public var canSave: Bool { qty >= 1 && qty <= maxQty && !isNoteOverLimit && unitPriceCents >= 0 }

    // MARK: - Init

    public init(lineId: UUID, itemName: String, qty: Int, unitPriceCents: Int, existingNote: String? = nil) {
        self.lineId = lineId
        self.itemName = itemName
        self.qty = qty
        self.unitPriceCents = unitPriceCents
        self.note = existingNote ?? ""
        self.discountMode = .none
    }

    // MARK: - Actions

    public func increment() {
        guard qty < maxQty else { return }
        qty += 1
    }

    public func decrement() {
        guard qty > 1 else { return }
        qty -= 1
    }

    public func applyToCart(_ cart: Cart) {
        cart.update(id: lineId, quantity: qty)
        cart.update(id: lineId, discountCents: derivedDiscountCents)
        cart.update(id: lineId, notes: note.isEmpty ? nil : note)
    }
}
