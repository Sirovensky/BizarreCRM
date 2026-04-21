import Foundation
import Networking

// MARK: - Export API endpoints

extension APIClient {

    /// POST /exports/tenant — start full tenant export (encrypted with passphrase)
    public func startTenantExport(passphrase: String) async throws -> StartExportResponse {
        let req = StartTenantExportRequest(passphrase: passphrase)
        return try await post("/exports/tenant", body: req, as: StartExportResponse.self)
    }

    /// POST /exports/domain/:entity — export one domain as CSV
    public func startDomainExport(entity: String, filters: [String: String]) async throws -> StartExportResponse {
        let req = StartDomainExportRequest(filters: filters)
        return try await post("/exports/domain/\(entity)", body: req, as: StartExportResponse.self)
    }

    /// POST /exports/customer/:id — GDPR individual package
    public func startCustomerExport(customerId: String) async throws -> StartExportResponse {
        return try await post(
            "/exports/customer/\(customerId)",
            body: EmptyBody(),
            as: StartExportResponse.self
        )
    }

    /// GET /exports/:id — poll status
    public func getExportStatus(id: String) async throws -> ExportStatusResponse {
        return try await get("/exports/\(id)", as: ExportStatusResponse.self)
    }

    /// GET /exports/:id/errors — optional errors list
    public func getExportErrors(id: String) async throws -> [ExportError] {
        return try await get("/exports/\(id)/errors", as: [ExportError].self)
    }

    /// GET /exports/schedules — list configured schedules
    public func listExportSchedules() async throws -> [ScheduledExport] {
        return try await get("/exports/schedules", as: [ScheduledExport].self)
    }

    /// POST /exports/schedules — create or update a schedule
    public func saveExportSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport {
        let req = SaveScheduleRequest(cadence: cadence, destination: destination)
        return try await post("/exports/schedules", body: req, as: ScheduledExport.self)
    }

    /// DELETE /exports/schedules/:id — remove a schedule
    public func deleteExportSchedule(id: String) async throws {
        try await delete("/exports/schedules/\(id)")
    }
}

// MARK: - Empty body helper (top-level to avoid Swift 6 generic nesting restriction)

private struct EmptyBody: Encodable, Sendable {}
