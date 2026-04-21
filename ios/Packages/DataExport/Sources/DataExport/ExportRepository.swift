import Foundation
import Networking

// MARK: - Protocol

public protocol ExportRepository: Sendable {
    func startTenantExport(passphrase: String) async throws -> ExportJob
    func startDomainExport(entity: String, filters: [String: String]) async throws -> ExportJob
    func startCustomerExport(customerId: String) async throws -> ExportJob
    func pollExport(id: String) async throws -> ExportJob
    func getErrors(id: String) async throws -> [ExportError]
    func listSchedules() async throws -> [ScheduledExport]
    func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport
    func deleteSchedule(id: String) async throws
}

// MARK: - Live implementation

public final class LiveExportRepository: ExportRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func startTenantExport(passphrase: String) async throws -> ExportJob {
        let resp = try await api.startTenantExport(passphrase: passphrase)
        return ExportJob(id: resp.exportId, scope: .fullTenant, status: .queued)
    }

    public func startDomainExport(entity: String, filters: [String: String]) async throws -> ExportJob {
        let resp = try await api.startDomainExport(entity: entity, filters: filters)
        return ExportJob(id: resp.exportId, scope: .domain, status: .queued)
    }

    public func startCustomerExport(customerId: String) async throws -> ExportJob {
        let resp = try await api.startCustomerExport(customerId: customerId)
        return ExportJob(id: resp.exportId, scope: .customer, status: .queued)
    }

    public func pollExport(id: String) async throws -> ExportJob {
        let resp = try await api.getExportStatus(id: id)
        // We don't have scope from the poll endpoint — preserve caller's scope by
        // returning a partial ExportJob. Callers merge into existing job.
        return ExportJob(
            id: id,
            scope: .fullTenant, // placeholder; caller overwrites scope from existing job
            status: resp.status,
            progressPct: resp.progressPct,
            downloadUrl: resp.downloadUrl,
            errorMessage: resp.errorMessage
        )
    }

    public func getErrors(id: String) async throws -> [ExportError] {
        try await api.getExportErrors(id: id)
    }

    public func listSchedules() async throws -> [ScheduledExport] {
        try await api.listExportSchedules()
    }

    public func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport {
        try await api.saveExportSchedule(cadence: cadence, destination: destination)
    }

    public func deleteSchedule(id: String) async throws {
        try await api.deleteExportSchedule(id: id)
    }
}
