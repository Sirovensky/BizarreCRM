import Foundation

// MARK: - §6 Inventory API — consolidation index
//
// All inventory-related APIClient extensions live in the Endpoints/ subdirectory
// of this package. This file is the canonical append-only home for any future
// inventory calls that do not warrant their own dedicated endpoint file.
//
// Current inventory endpoints:
//
//  Endpoints/InventoryEndpoints.swift
//    listInventory(filter:keyword:pageSize:)             GET  /api/v1/inventory
//    adjustStock(itemId:request:)                        POST /api/v1/inventory/:id/adjust-stock
//    listLowStock()                                      GET  /api/v1/inventory/low-stock
//
//  Endpoints/InventoryRequests.swift
//    createInventoryItem(_:)                             POST /api/v1/inventory
//    updateInventoryItem(id:_:)                          PUT  /api/v1/inventory/:id
//
//  Endpoints/InventoryDetailEndpoints.swift
//    (item detail + stock movements)                     GET  /api/v1/inventory/:id
//
//  Endpoints/InventoryReceivingEndpoints.swift
//    listReceivingOrders(status:page:)                   GET  /api/v1/inventory/purchase-orders/list
//    receivingOrder(id:)                                 GET  /api/v1/inventory/purchase-orders/:id
//    finalizeReceiving(id:request:)                      POST /api/v1/inventory/purchase-orders/:id/receive
//    scanReceive(_:)                                     POST /api/v1/inventory/receive-scan
//
//  Endpoints/InventoryVariants.swift  (see VariantEndpoints.swift in Inventory pkg)
//  Endpoints/InventoryBatchEndpoints.swift
//  Endpoints/InventoryBarcodeEndpoints.swift
//  Endpoints/InventoryStocktakeEndpoints.swift

// MARK: - §6.1 Sort + advanced filter DTOs

/// Sort options for `GET /api/v1/inventory`.
/// Maps `sort_by` + `sort_dir` query params accepted by the server.
public enum InventorySortOption: String, CaseIterable, Sendable, Identifiable {
    case nameAsc      = "name_asc"
    case nameDesc     = "name_desc"
    case skuAsc       = "sku_asc"
    case stockAsc     = "stock_asc"
    case stockDesc    = "stock_desc"
    case priceAsc     = "price_asc"
    case priceDesc    = "price_desc"
    case lastRestock  = "last_restock"
    case lastSold     = "last_sold"
    case margin       = "margin"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nameAsc:     return "Name A→Z"
        case .nameDesc:    return "Name Z→A"
        case .skuAsc:      return "SKU"
        case .stockAsc:    return "Stock (low first)"
        case .stockDesc:   return "Stock (high first)"
        case .priceAsc:    return "Price (low first)"
        case .priceDesc:   return "Price (high first)"
        case .lastRestock: return "Last restocked"
        case .lastSold:    return "Last sold"
        case .margin:      return "Margin %"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .nameAsc:     return [.init(name: "sort_by", value: "name"),
                                   .init(name: "sort_dir", value: "asc")]
        case .nameDesc:    return [.init(name: "sort_by", value: "name"),
                                   .init(name: "sort_dir", value: "desc")]
        case .skuAsc:      return [.init(name: "sort_by", value: "sku"),
                                   .init(name: "sort_dir", value: "asc")]
        case .stockAsc:    return [.init(name: "sort_by", value: "in_stock"),
                                   .init(name: "sort_dir", value: "asc")]
        case .stockDesc:   return [.init(name: "sort_by", value: "in_stock"),
                                   .init(name: "sort_dir", value: "desc")]
        case .priceAsc:    return [.init(name: "sort_by", value: "retail_price"),
                                   .init(name: "sort_dir", value: "asc")]
        case .priceDesc:   return [.init(name: "sort_by", value: "retail_price"),
                                   .init(name: "sort_dir", value: "desc")]
        case .lastRestock: return [.init(name: "sort_by", value: "last_restocked_at"),
                                   .init(name: "sort_dir", value: "desc")]
        case .lastSold:    return [.init(name: "sort_by", value: "last_sold_at"),
                                   .init(name: "sort_dir", value: "desc")]
        case .margin:      return [.init(name: "sort_by", value: "margin"),
                                   .init(name: "sort_dir", value: "desc")]
        }
    }
}

/// Advanced filter parameters beyond `InventoryFilter` (type tab).
/// Combined with the primary filter when calling `listInventoryAdvanced(…)`.
public struct InventoryAdvancedFilter: Sendable, Hashable {
    public var manufacturer: String?
    public var supplier: String?
    public var category: String?
    public var minPriceCents: Int?
    public var maxPriceCents: Int?
    public var hideOutOfStock: Bool
    public var reorderableOnly: Bool
    public var lowStockOnly: Bool

    public init(
        manufacturer: String? = nil,
        supplier: String? = nil,
        category: String? = nil,
        minPriceCents: Int? = nil,
        maxPriceCents: Int? = nil,
        hideOutOfStock: Bool = false,
        reorderableOnly: Bool = false,
        lowStockOnly: Bool = false
    ) {
        self.manufacturer = manufacturer
        self.supplier = supplier
        self.category = category
        self.minPriceCents = minPriceCents
        self.maxPriceCents = maxPriceCents
        self.hideOutOfStock = hideOutOfStock
        self.reorderableOnly = reorderableOnly
        self.lowStockOnly = lowStockOnly
    }

    public var isEmpty: Bool {
        manufacturer == nil && supplier == nil && category == nil
        && minPriceCents == nil && maxPriceCents == nil
        && !hideOutOfStock && !reorderableOnly && !lowStockOnly
    }

    public var queryItems: [URLQueryItem] {
        var result: [URLQueryItem] = []
        if let manufacturer { result.append(.init(name: "manufacturer", value: manufacturer)) }
        if let supplier     { result.append(.init(name: "supplier", value: supplier)) }
        if let category     { result.append(.init(name: "category", value: category)) }
        if let min = minPriceCents { result.append(.init(name: "min_price_cents", value: "\(min)")) }
        if let max = maxPriceCents { result.append(.init(name: "max_price_cents", value: "\(max)")) }
        if hideOutOfStock  { result.append(.init(name: "hide_out_of_stock", value: "true")) }
        if reorderableOnly { result.append(.init(name: "reorderable_only", value: "true")) }
        if lowStockOnly    { result.append(.init(name: "low_stock", value: "true")) }
        return result
    }
}

// MARK: - Extended list call with sort + advanced filter

public extension APIClient {
    /// `GET /api/v1/inventory` extended with sort + advanced filter params.
    /// Falls through to `listInventory(filter:keyword:pageSize:)` internally
    /// by composing query items. Uses the same server route.
    func listInventoryAdvanced(
        filter: InventoryFilter = .all,
        sort: InventorySortOption = .nameAsc,
        advanced: InventoryAdvancedFilter = .init(),
        keyword: String? = nil,
        pageSize: Int = 50
    ) async throws -> InventoryListResponse {
        var query = filter.queryItems + sort.queryItems + advanced.queryItems
        query.append(.init(name: "pagesize", value: "\(pageSize)"))
        if let keyword, !keyword.isEmpty {
            query.append(.init(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/inventory", query: query, as: InventoryListResponse.self)
    }
}
