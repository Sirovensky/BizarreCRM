import Foundation
import Networking

// MARK: - §19.5 OrganizationSettingsRepository protocol

/// Contract for reading and writing organisation-level settings.
public protocol OrganizationSettingsRepository: Sendable {
    /// Fetch the current organisation settings from the server.
    func fetch() async throws -> OrganizationSettings
    /// Persist updated settings and return the confirmed value.
    func save(_ settings: OrganizationSettings) async throws -> OrganizationSettings
}

// MARK: - Live implementation

/// Bridges `GET /settings/store` + `PUT /settings/store` to `OrganizationSettings`.
public struct LiveOrganizationSettingsRepository: OrganizationSettingsRepository {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetch() async throws -> OrganizationSettings {
        let cfg = try await api.fetchOrganizationConfig()
        return OrganizationSettings(storeConfig: cfg)
    }

    public func save(_ settings: OrganizationSettings) async throws -> OrganizationSettings {
        let cfg = try await api.updateOrganizationConfig(settings.toStoreConfig())
        return OrganizationSettings(storeConfig: cfg)
    }
}

// MARK: - APIClient endpoints

public extension APIClient {

    /// `GET /settings/store` — returns the flat store_config map.
    func fetchOrganizationConfig() async throws -> [String: String] {
        try await get("/settings/store", as: [String: String].self)
    }

    /// `PUT /settings/store` — upserts all provided key/value pairs.
    @discardableResult
    func updateOrganizationConfig(_ body: [String: String]) async throws -> [String: String] {
        try await put("/settings/store", body: body, as: [String: String].self)
    }
}
