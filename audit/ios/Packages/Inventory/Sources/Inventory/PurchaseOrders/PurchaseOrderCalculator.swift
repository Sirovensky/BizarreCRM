import Foundation

// MARK: - PurchaseOrderCalculator

/// Pure, stateless calculator for PO financials and receive-progress.
/// All money in cents. Functions are static so they can be tested without constructing a live object.
public enum PurchaseOrderCalculator {

    /// Sum of all line totals. Returns the pre-computed `lineTotalCents` values.
    public static func totalCents(lines: [POLineItem]) -> Int {
        lines.reduce(0) { $0 + $1.lineTotalCents }
    }

    /// Returns a value in [0, 1] representing the fraction of qty received
    /// across all lines. Returns 0 for an empty PO.
    public static func receivedProgress(po: PurchaseOrder) -> Double {
        let totalOrdered  = po.items.reduce(0) { $0 + $1.qtyOrdered }
        let totalReceived = po.items.reduce(0) { $0 + $1.qtyReceived }
        guard totalOrdered > 0 else { return 0 }
        return min(1.0, Double(totalReceived) / Double(totalOrdered))
    }

    /// Recomputed unit cost × qty for a line. Useful for draft POs whose
    /// `lineTotalCents` may not yet be persisted.
    public static func lineTotal(unitCostCents: Int, qty: Int) -> Int {
        unitCostCents * qty
    }
}
