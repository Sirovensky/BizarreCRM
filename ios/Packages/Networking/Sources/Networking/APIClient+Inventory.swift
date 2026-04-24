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
