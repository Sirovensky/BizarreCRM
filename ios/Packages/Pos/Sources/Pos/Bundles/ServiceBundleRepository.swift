import Foundation
import Networking
import Core

// MARK: - Server-route contract
//
// Expected: GET /api/v1/inventory/items/:id/bundle
//
// Request:  GET /api/v1/inventory/items/42/bundle
//           (no query parameters)
//
// Response envelope (standard BizarreCRM { success, data }):
// {
//   "success": true,
//   "data": {
//     "bundle_id": "…UUID string…",    // optional; server may omit
//     "required": [
//       {
//         "id": 123,
//         "sku": "IPH14P-S",
//         "name": "iPhone 14 Pro Screen — OEM",
//         "price_cents": 8999,
//         "is_service": false,
//         "stock_qty": 4           // optional
//       }
//     ],
//     "optional": [...]
//   }
// }
//
// 404 → the item has no BOM; treat as empty bundle (graceful degradation).
// 501 → server route not yet deployed; Live repo throws .notImplemented so
//        the UI falls back to a modal part-picker.

// MARK: - Raw server DTO

/// Wire-format struct for one child item returned by the bundle endpoint.
private struct BundleChildDTO: Decodable, Sendable {
    let id: Int64
    let sku: String
    let name: String
    let priceCents: Int
    let isService: Bool
    let stockQty: Int?

    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case priceCents  = "price_cents"
        case isService   = "is_service"
        case stockQty    = "stock_qty"
    }

    var asRef: InventoryItemRef {
        InventoryItemRef(
            id: id,
            sku: sku,
            name: name,
            priceCents: priceCents,
            isService: isService,
            stockQty: stockQty
        )
    }
}

private struct BundleResponseDTO: Decodable, Sendable {
    let bundleId: String?
    let required: [BundleChildDTO]
    let optional: [BundleChildDTO]

    enum CodingKeys: String, CodingKey {
        case bundleId  = "bundle_id"
        case required
        case optional
    }
}

// MARK: - Error type

/// Errors specific to bundle resolution.
public enum ServiceBundleError: Error, Sendable {
    /// The server route `GET /inventory/items/:id/bundle` does not exist yet.
    /// The UI should fall back to a modal part-picker.
    case notImplemented
    /// The network request failed for an unexpected reason.
    case networkError(Error)
}

// MARK: - Protocol

/// Fetches the service-bundle definition for a given inventory item.
///
/// Conformers:
/// - `ServiceBundleRepositoryLive`  — calls the real server route.
/// - `ServiceBundleRepositoryStub`  — returns empty results for build
///   compatibility while the server route is pending.
public protocol ServiceBundleRepository: Sendable {
    /// Returns the bundle definition for `serviceItemId`.
    ///
    /// - Returns: Raw required + optional children (not device-filtered).
    ///   Device-aware filtering is performed by `ServiceBundleResolver`.
    /// - Throws: `ServiceBundleError.notImplemented` when the route is absent.
    func fetchBundle(serviceItemId: Int64) async throws -> BundleResolution
}

// MARK: - Live implementation

/// Calls `GET /api/v1/inventory/items/:id/bundle`.
/// Gracefully degrades to an empty bundle on 404.
/// Throws `ServiceBundleError.notImplemented` on 501 / route missing.
public struct ServiceBundleRepositoryLive: ServiceBundleRepository {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchBundle(serviceItemId: Int64) async throws -> BundleResolution {
        let path = "/api/v1/inventory/items/\(serviceItemId)/bundle"

        let dto: BundleResponseDTO
        do {
            dto = try await api.get(path, as: BundleResponseDTO.self)
        } catch {
            // Treat HTTP 404 as "no BOM defined" → empty bundle.
            if isNotFound(error) {
                AppLog.pos.info("ServiceBundleRepository: no bundle for item \(serviceItemId) (404) — treating as empty")
                return .empty()
            }
            // HTTP 501 / route not yet deployed → caller falls back to picker.
            if isNotImplemented(error) {
                AppLog.pos.error("ServiceBundleRepository: server route not yet deployed for item \(serviceItemId)")
                throw ServiceBundleError.notImplemented
            }
            AppLog.pos.error("ServiceBundleRepository: network error for item \(serviceItemId): \(error.localizedDescription, privacy: .public)")
            throw ServiceBundleError.networkError(error)
        }

        let bundleId = dto.bundleId.flatMap { UUID(uuidString: $0) } ?? UUID()

        return BundleResolution(
            required: dto.required.map(\.asRef),
            optional: dto.optional.map(\.asRef),
            bundleId: bundleId,
            requiresPartPicker: false
        )
    }

    // MARK: - HTTP status helpers

    private func isNotFound(_ error: Error) -> Bool {
        // BizarreCRM APIClient throws URLError or a custom HTTPError with the
        // status code.  We check both common patterns without force-casting.
        let description = error.localizedDescription.lowercased()
        if description.contains("404") { return true }
        if let urlError = error as? URLError, urlError.code == .resourceUnavailable { return true }
        return false
    }

    private func isNotImplemented(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("501")
            || description.contains("not implemented")
    }
}

// MARK: - Stub implementation

/// Returns empty bundles for every item.  Used while the server route
/// `GET /inventory/items/:id/bundle` is pending deployment.
///
/// The Stub never throws — the cart add proceeds without children, giving
/// the cashier a graceful "no bundle" experience identical to an item with
/// no BOM data.
public struct ServiceBundleRepositoryStub: ServiceBundleRepository {
    public init() {}

    public func fetchBundle(serviceItemId: Int64) async throws -> BundleResolution {
        AppLog.pos.debug("ServiceBundleRepositoryStub: returning empty bundle for item \(serviceItemId)")
        return .empty()
    }
}
