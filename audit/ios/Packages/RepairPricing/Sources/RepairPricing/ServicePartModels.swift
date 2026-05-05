import Foundation
import Core

// MARK: - §43.4 Part Mapping Models

/// One SKU + quantity row in a multi-part repair bundle.
public struct ServicePartBundle: Codable, Sendable, Hashable, Identifiable {
    /// Use skuId as stable identity within a bundle list.
    public var id: String { skuId }
    public var skuId: String
    public var qty: Int

    public init(skuId: String, qty: Int = 1) {
        self.skuId = skuId
        self.qty = qty
    }
}

/// PATCH /repair-pricing/services/:id body for part mapping update.
public struct UpdateServicePartsRequest: Encodable, Sendable {
    let primarySkuId: String?
    let bundle: [ServicePartBundle]

    enum CodingKeys: String, CodingKey {
        case primarySkuId = "primary_sku_id"
        case bundle
    }
}
