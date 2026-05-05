import Foundation
import Networking

// MARK: - APIClient + Mileage endpoints
//
// Server: POST /api/v1/expenses/mileage
// Request body: CreateMileageBody (MileageEntry.swift)
// Response: MileageEntry (MileageEntry.swift)
//
// This extension lives in the Expenses package (not Networking) because
// MileageEntry / CreateMileageBody are defined here — moving them to Networking
// would create cross-package DTO duplication.

public extension APIClient {

    /// `POST /api/v1/expenses/mileage` — log a mileage trip.
    /// Requires a valid employee session. Returns the created `MileageEntry`.
    func createMileageEntry(_ body: CreateMileageBody) async throws -> MileageEntry {
        try await post("/api/v1/expenses/mileage", body: body, as: MileageEntry.self)
    }
}
