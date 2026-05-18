import Foundation

// MARK: - Inventory create

/// `POST /api/v1/inventory` request body.
/// Server: packages/server/src/routes/inventory.routes.ts:944.
///
/// Required: `name`, `item_type` (enum — "product" | "part" | "service").
/// Server validates prices + quantities and auto-generates SKU when blank —
/// we still send ours so the operator can dictate it.
public struct CreateInventoryItemRequest: Codable, Sendable {
    public let name: String
    public let itemType: String
    public let sku: String?
    public let upc: String?
    public let description: String?
    public let category: String?
    public let manufacturer: String?
    public let costPrice: Double?
    public let retailPrice: Double?
    public let inStock: Int?
    public let reorderLevel: Int?
    public let supplierId: Int64?

    public init(name: String,
                itemType: String = "product",
                sku: String? = nil,
                upc: String? = nil,
                description: String? = nil,
                category: String? = nil,
                manufacturer: String? = nil,
                costPrice: Double? = nil,
                retailPrice: Double? = nil,
                inStock: Int? = nil,
                reorderLevel: Int? = nil,
                supplierId: Int64? = nil) {
        self.name = name
        self.itemType = itemType
        self.sku = sku
        self.upc = upc
        self.description = description
        self.category = category
        self.manufacturer = manufacturer
        self.costPrice = costPrice
        self.retailPrice = retailPrice
        self.inStock = inStock
        self.reorderLevel = reorderLevel
        self.supplierId = supplierId
    }

    enum CodingKeys: String, CodingKey {
        case name, sku, upc, description, category, manufacturer
        case itemType = "item_type"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case inStock = "in_stock"
        case reorderLevel = "reorder_level"
        case supplierId = "supplier_id"
    }
}

// MARK: - Inventory update

/// `PUT /api/v1/inventory/:id` request body.
/// Server: packages/server/src/routes/inventory.routes.ts:1011.
///
/// All fields are optional — the server uses COALESCE to preserve missing
/// keys, so omit to leave a column untouched. Send empty string to clear a
/// nullable field (per route comment at line 1054).
public struct UpdateInventoryItemRequest: Codable, Sendable {
    public let name: String?
    public let itemType: String?
    public let sku: String?
    public let upc: String?
    public let description: String?
    public let category: String?
    public let manufacturer: String?
    public let costPrice: Double?
    public let retailPrice: Double?
    public let reorderLevel: Int?
    public let supplierId: Int64?

    public init(name: String? = nil,
                itemType: String? = nil,
                sku: String? = nil,
                upc: String? = nil,
                description: String? = nil,
                category: String? = nil,
                manufacturer: String? = nil,
                costPrice: Double? = nil,
                retailPrice: Double? = nil,
                reorderLevel: Int? = nil,
                supplierId: Int64? = nil) {
        self.name = name
        self.itemType = itemType
        self.sku = sku
        self.upc = upc
        self.description = description
        self.category = category
        self.manufacturer = manufacturer
        self.costPrice = costPrice
        self.retailPrice = retailPrice
        self.reorderLevel = reorderLevel
        self.supplierId = supplierId
    }

    enum CodingKeys: String, CodingKey {
        case name, sku, upc, description, category, manufacturer
        case itemType = "item_type"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case reorderLevel = "reorder_level"
        case supplierId = "supplier_id"
    }
}

// MARK: - §6.1 Import CSV/JSON

/// `POST /api/v1/inventory/import-csv` request body.
///
/// BUGHUNT-2026-05-17: server destructures `{ items: [...] }` from the body
/// (see inventory.routes.ts ~L246) — it does NOT accept a raw CSV string.
/// Previous iOS code sent `{ csv_data: "name,sku,..." }` so the import
/// always failed with "items array is required". Parse the CSV client-side
/// here at the encoder boundary so the public Sheet API (which still passes
/// `csvData:`) doesn't have to change.
public struct InventoryImportCSVRequest: Encodable, Sendable {
    public let csvData: String

    public init(csvData: String) { self.csvData = csvData }

    enum CodingKeys: String, CodingKey {
        case items
    }

    /// One row of the parsed CSV, mapped to the server's `ValidatedRow`
    /// expected by the import handler. Server fields:
    /// `name`, `sku`, `item_type`, `in_stock`, `retail_price`, `cost_price`,
    /// `reorder_level`, `category`, `manufacturer`, `description`, `supplier_id`.
    /// We only emit the columns the legacy UI writes plus a fallback `item_type`.
    private struct ImportItem: Encodable, Sendable {
        let name: String
        let sku: String?
        let in_stock: Int?
        let retail_price: Double?
        let item_type: String

        enum CodingKeys: String, CodingKey {
            case name, sku, in_stock, retail_price, item_type
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let items = Self.parse(csv: csvData)
        try c.encode(items, forKey: .items)
    }

    /// Parse the legacy `name,sku,quantity,retail_price` CSV shape into the
    /// server's expected item rows. Empty / malformed rows are skipped — the
    /// server validates again and reports per-row errors.
    private static func parse(csv: String) -> [ImportItem] {
        let lines = csv.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline })
        guard lines.count > 1 else { return [] }
        // First line is the header; we know its shape from the sheet
        // (`name,sku,quantity,retail_price`), so we hard-map by index.
        var rows: [ImportItem] = []
        for line in lines.dropFirst() {
            let cols = splitCSVLine(String(line))
            guard !cols.isEmpty else { continue }
            let name = unquote(cols[safe: 0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let sku = unquote(cols[safe: 1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let qty = Int(unquote(cols[safe: 2] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let priceStr = unquote(cols[safe: 3] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let price = Double(priceStr) ?? 0
            rows.append(ImportItem(
                name: name,
                sku: sku.isEmpty ? nil : sku,
                in_stock: qty,
                retail_price: price,
                item_type: "product"
            ))
        }
        return rows
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        // Minimal RFC-4180-ish split that respects quoted commas. Same
        // approximation the import sheet uses on the parse side.
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if ch == "," && !inQuotes {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current)
        return out
    }

    private static func unquote(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") { t.removeFirst() }
        if t.hasSuffix("\"") { t.removeLast() }
        return t.replacingOccurrences(of: "\"\"", with: "\"")
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}

/// Response from `POST /api/v1/inventory/import-csv`.
public struct InventoryImportResult: Decodable, Sendable {
    public let imported: Int
    public let errors: [InventoryImportRowError]

    public init(imported: Int, errors: [InventoryImportRowError]) {
        self.imported = imported
        self.errors = errors
    }
}

public struct InventoryImportRowError: Decodable, Sendable, Identifiable {
    public var id: Int { row }
    public let row: Int
    public let message: String
}

// MARK: - §6.2 Tax class update

/// `PATCH /api/v1/inventory/:id` — sparse update for tax class.
public struct InventoryTaxClassRequest: Encodable, Sendable {
    public let taxClass: String

    public init(taxClass: String) { self.taxClass = taxClass }

    enum CodingKeys: String, CodingKey {
        case taxClass = "tax_class"
    }
}

public extension APIClient {
    /// Server responds `201 { success: true, data: <full row> }`. We decode
    /// only `id` for navigation — mirrors `createCustomer`'s contract.
    func createInventoryItem(_ req: CreateInventoryItemRequest) async throws -> CreatedResource {
        try await post("/api/v1/inventory", body: req, as: CreatedResource.self)
    }

    /// Server responds `200 { success: true, data: <full row> }`.
    func updateInventoryItem(id: Int64, _ req: UpdateInventoryItemRequest) async throws -> CreatedResource {
        try await put("/api/v1/inventory/\(id)", body: req, as: CreatedResource.self)
    }

    /// §6.2 Soft-deactivate (DELETE /api/v1/inventory/:id).
    /// Server sets is_active = 0; preserves all historical references.
    func deactivateInventoryItem(id: Int64) async throws {
        try await delete("/api/v1/inventory/\(id)")
    }

    /// §6.2 Update tax class (admin only). PATCH /api/v1/inventory/:id
    @discardableResult
    func updateInventoryTaxClass(id: Int64, taxClass: String) async throws -> CreatedResource {
        try await patch("/api/v1/inventory/\(id)",
                        body: InventoryTaxClassRequest(taxClass: taxClass),
                        as: CreatedResource.self)
    }
}
