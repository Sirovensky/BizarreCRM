import Foundation

// MARK: - Barcode

/// A scanned barcode value with its symbology.
///
/// Published by ``BarcodeScannerView`` via `onScan`. Immutable + Sendable so
/// it crosses actor boundaries safely.
public struct Barcode: Equatable, Sendable {
    /// The raw string payload decoded from the barcode.
    public let value: String
    /// Symbology as a human-readable string (e.g. "ean13", "qr", "code128").
    public let symbology: String

    public init(value: String, symbology: String) {
        self.value = value
        self.symbology = symbology
    }
}

// MARK: - BarcodeLookupResult

/// Result returned by an inventory barcode lookup.
///
/// Mirrors the `GET /api/v1/inventory/barcode/:code` server response
/// (packages/server/src/routes/inventory.routes.ts:548).
public struct BarcodeLookupResult: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String?
    public let sku: String?
    public let upc: String?
    public let inStock: Int?
    public let retailPrice: Double?
    public let itemType: String?

    public var displayName: String { name?.isEmpty == false ? name! : "Unnamed" }

    enum CodingKeys: String, CodingKey {
        case id, name, sku, upc
        case inStock = "in_stock"
        case retailPrice = "retail_price"
        case itemType = "item_type"
    }
}

// MARK: - BarcodeError

/// Domain errors raised by the barcode scanner and lookup path.
public enum BarcodeError: LocalizedError, Sendable {
    case notAuthorized
    case unavailable
    case notFound(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access is required to scan barcodes. Enable it in Settings."
        case .unavailable:
            return "The barcode scanner is not available on this device."
        case .notFound(let code):
            return "No inventory item found for barcode \"\(code)\"."
        case .networkError(let detail):
            return "Barcode lookup failed: \(detail)."
        }
    }
}
