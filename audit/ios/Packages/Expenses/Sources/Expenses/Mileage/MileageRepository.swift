import Foundation
import Networking
import Core

// MARK: - MileageRepository

/// §20 containment-compliant repository for mileage entries.
/// All calls to `APIClient` for mileage are funnelled through this protocol.
public protocol MileageRepository: Sendable {
    /// Log a new mileage trip. Returns the server-created `MileageEntry`.
    func create(_ body: CreateMileageBody) async throws -> MileageEntry
}

// MARK: - LiveMileageRepository

public actor LiveMileageRepository: MileageRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func create(_ body: CreateMileageBody) async throws -> MileageEntry {
        try await api.createMileageEntry(body)
    }
}
