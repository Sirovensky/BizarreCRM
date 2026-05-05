import Foundation

// MARK: - §6.11 Bundle Unpacker (pure)

/// Pure helper — no UIKit / network dependencies.
/// When a bundle is sold at POS, decrement component SKUs (not the bundle SKU itself).
public enum BundleUnpacker {

    // MARK: - Unpack result

    /// A component SKU + quantity to decrement.
    public struct DecrementInstruction: Sendable, Equatable {
        public let sku: String
        public let qty: Int

        public init(sku: String, qty: Int) {
            self.sku = sku
            self.qty = qty
        }
    }

    /// Warning emitted when a component SKU is missing (empty componentSKU).
    public struct MissingComponentWarning: Sendable, Equatable {
        public let index: Int
        public let reason: String

        public init(index: Int, reason: String) {
            self.index = index
            self.reason = reason
        }
    }

    // MARK: - Unpack

    /// Returns the list of (sku, qty) decrements needed when `quantity` bundles are sold.
    /// - Parameters:
    ///   - bundle: The bundle being sold.
    ///   - quantity: Number of bundles sold (multiplier).
    /// - Returns: Array of decrement instructions — one per component × quantity.
    public static func unpack(
        bundle: InventoryBundle,
        quantity: Int
    ) -> [DecrementInstruction] {
        guard quantity > 0 else { return [] }
        return bundle.components.compactMap { component in
            guard !component.componentSKU.isEmpty else { return nil }
            return DecrementInstruction(sku: component.componentSKU, qty: component.qty * quantity)
        }
    }

    /// Validates bundle components and returns any warnings for missing/invalid entries.
    public static func validate(
        bundle: InventoryBundle
    ) -> [MissingComponentWarning] {
        bundle.components.enumerated().compactMap { idx, component in
            if component.componentSKU.trimmingCharacters(in: .whitespaces).isEmpty {
                return MissingComponentWarning(index: idx, reason: "Component SKU at index \(idx) is empty.")
            }
            if component.qty <= 0 {
                return MissingComponentWarning(index: idx, reason: "Component \(component.componentSKU) has qty \(component.qty) ≤ 0.")
            }
            return nil
        }
    }
}
