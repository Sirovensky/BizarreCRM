import Foundation

// MARK: - §6.11 Inventory Bundle

/// A bundle is a single SKU sold as a unit but composed of multiple sub-SKUs.
/// Example: "Screen Repair Kit" = Screen + Battery + Adhesive.
/// All money in cents.
public struct InventoryBundle: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// The bundle's own unique SKU.
    public let sku: String
    public let name: String
    /// Component sub-SKUs and their quantities.
    public let components: [BundleComponent]
    /// Bundle selling price (may differ from individual sum).
    public let bundlePriceCents: Int
    /// Informational: sum of component retail prices at list price.
    public let individualPriceSum: Int

    public init(
        id: Int64,
        sku: String,
        name: String,
        components: [BundleComponent],
        bundlePriceCents: Int,
        individualPriceSum: Int
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.components = components
        self.bundlePriceCents = bundlePriceCents
        self.individualPriceSum = individualPriceSum
    }

    /// True when bundle price is less than individual sum (i.e. a discount).
    public var isSavingsBundle: Bool {
        bundlePriceCents < individualPriceSum
    }

    /// Savings amount in cents (0 if no savings).
    public var savingsCents: Int {
        max(0, individualPriceSum - bundlePriceCents)
    }

    enum CodingKeys: String, CodingKey {
        case id, sku, name, components
        case bundlePriceCents   = "bundle_price_cents"
        case individualPriceSum = "individual_price_sum"
    }
}

// MARK: - Bundle Component

/// One component of a bundle.
public struct BundleComponent: Codable, Sendable, Hashable {
    public let componentSKU: String
    public let qty: Int

    public init(componentSKU: String, qty: Int) {
        self.componentSKU = componentSKU
        self.qty = qty
    }

    enum CodingKeys: String, CodingKey {
        case componentSKU = "component_sku"
        case qty
    }
}
