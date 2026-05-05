import Foundation
import Networking

// §5.7 — Protocol + live implementation for customer asset persistence.
// All network calls go inline via APIClient.get / .post — no APIClient+X extension.

// MARK: - Protocol

public protocol CustomerAssetsRepository: Sendable {
    func fetchAssets(customerId: Int64) async throws -> [CustomerAsset]
    func addAsset(customerId: Int64, request: CreateCustomerAssetRequest) async throws -> CustomerAsset
}

// MARK: - Live implementation

public struct CustomerAssetsRepositoryImpl: CustomerAssetsRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// `GET /api/v1/customers/:id/assets` — returns array, unwraps envelope.
    public func fetchAssets(customerId: Int64) async throws -> [CustomerAsset] {
        try await api.get(
            "/api/v1/customers/\(customerId)/assets",
            as: [CustomerAsset].self
        )
    }

    /// `POST /api/v1/customers/:id/assets` — creates and returns the new asset.
    public func addAsset(
        customerId: Int64,
        request: CreateCustomerAssetRequest
    ) async throws -> CustomerAsset {
        try await api.post(
            "/api/v1/customers/\(customerId)/assets",
            body: request,
            as: CustomerAsset.self
        )
    }
}
