import Foundation
import Networking

// MARK: - ExportClientError

public enum ExportClientError: LocalizedError, Sendable {
    case missingData(String)

    public var errorDescription: String? {
        switch self {
        case .missingData(let detail):
            return detail
        }
    }
}

// MARK: - ExportRepository protocol

/// All network calls for §49 Data Export go through this protocol.
/// UI/ViewModels depend on the protocol; tests inject MockExportRepository.
public protocol ExportRepository: Sendable {
    // Tenant async job
    func startTenantExport(passphrase: String) async throws -> TenantExportJob
    func pollTenantExport(jobId: Int) async throws -> TenantExportJob
    func fetchDataExportRateStatus() async throws -> DataExportRateStatus

    // GDPR
    func eraseCustomerPII(customerId: Int, confirmName: String) async throws

    // Schedule CRUD
    func listSchedules() async throws -> [ExportSchedule]
    func getSchedule(id: Int) async throws -> ScheduleDetail
    func createSchedule(_ request: CreateScheduleRequest) async throws -> ExportSchedule
    func updateSchedule(id: Int, request: UpdateScheduleRequest) async throws -> ExportSchedule
    func pauseSchedule(id: Int) async throws
    func resumeSchedule(id: Int) async throws
    func cancelSchedule(id: Int) async throws

    // Settings export/import
    func fetchSettingsExport() async throws -> SettingsExportPayload
    func importSettings(payload: [String: String]) async throws -> SettingsImportResult
    func fetchShopTemplates() async throws -> [ShopTemplate]
    func applyShopTemplate(id: String) async throws

    // Legacy: ExportJob-based API for ExportProgressViewModel compatibility
    func startLegacyTenantExport(passphrase: String) async throws -> ExportJob
    func pollExport(id: String) async throws -> ExportJob
    func getErrors(id: String) async throws -> [ExportError]
    func listLegacySchedules() async throws -> [ScheduledExport]
    func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport
    func deleteSchedule(id: String) async throws
}

// MARK: - LiveExportRepository

public final class LiveExportRepository: ExportRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Tenant async job

    public func startTenantExport(passphrase: String) async throws -> TenantExportJob {
        let resp = try await api.startTenantExportJob(passphrase: passphrase)
        return TenantExportJob(id: resp.jobId, status: .queued)
    }

    public func pollTenantExport(jobId: Int) async throws -> TenantExportJob {
        return try await api.pollTenantExportJob(jobId: jobId)
    }

    public func fetchDataExportRateStatus() async throws -> DataExportRateStatus {
        return try await api.fetchDataExportRateStatus()
    }

    // MARK: - GDPR

    public func eraseCustomerPII(customerId: Int, confirmName: String) async throws {
        try await api.eraseCustomerPII(customerId: customerId, confirmName: confirmName)
    }

    // MARK: - Schedules

    public func listSchedules() async throws -> [ExportSchedule] {
        return try await api.listExportSchedules()
    }

    public func getSchedule(id: Int) async throws -> ScheduleDetail {
        let raw = try await api.getExportSchedule(id: id)
        return ScheduleDetail(schedule: raw.schedule, recentRuns: raw.recentRuns)
    }

    public func createSchedule(_ request: CreateScheduleRequest) async throws -> ExportSchedule {
        return try await api.createExportSchedule(request)
    }

    public func updateSchedule(id: Int, request: UpdateScheduleRequest) async throws -> ExportSchedule {
        return try await api.updateExportSchedule(id: id, request: request)
    }

    public func pauseSchedule(id: Int) async throws {
        try await api.pauseExportSchedule(id: id)
    }

    public func resumeSchedule(id: Int) async throws {
        try await api.resumeExportSchedule(id: id)
    }

    public func cancelSchedule(id: Int) async throws {
        try await api.cancelExportSchedule(id: id)
    }

    // MARK: - Settings export/import

    public func fetchSettingsExport() async throws -> SettingsExportPayload {
        return try await api.fetchSettingsExport()
    }

    public func importSettings(payload: [String: String]) async throws -> SettingsImportResult {
        return try await api.importSettings(payload: payload)
    }

    public func fetchShopTemplates() async throws -> [ShopTemplate] {
        return try await api.fetchShopTemplates()
    }

    public func applyShopTemplate(id: String) async throws {
        try await api.applyShopTemplate(id: id)
    }

    // MARK: - Legacy ExportJob shim (for ExportProgressViewModel)

    public func startLegacyTenantExport(passphrase: String) async throws -> ExportJob {
        let resp = try await api.startTenantExportJob(passphrase: passphrase)
        return ExportJob(id: String(resp.jobId), scope: .fullTenant, status: .queued)
    }

    public func pollExport(id: String) async throws -> ExportJob {
        guard let jobId = Int(id) else {
            throw ExportClientError.missingData("pollExport: invalid id \(id)")
        }
        let job = try await api.pollTenantExportJob(jobId: jobId)
        return ExportJob(
            id: id,
            scope: .fullTenant,
            status: job.status,
            progressPct: job.status.progress,
            downloadUrl: job.downloadUrl,
            errorMessage: job.errorMessage
        )
    }

    public func getErrors(id: String) async throws -> [ExportError] {
        // Server does not expose a /errors sub-endpoint; return empty.
        return []
    }

    public func listLegacySchedules() async throws -> [ScheduledExport] {
        // Legacy shim — convert new ExportSchedule list to old ScheduledExport shape
        let schedules = try await api.listExportSchedules()
        return schedules.map { s in
            ScheduledExport(
                id: String(s.id),
                cadence: ExportCadence(rawValue: s.intervalKind.rawValue) ?? .daily,
                destination: .icloud,
                lastRunAt: nil,
                nextRunAt: s.nextRunAt.flatMap { parseISO($0) }
            )
        }
    }

    public func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport {
        let req = CreateScheduleRequest(
            name: "\(cadence.displayName) export",
            exportType: .full,
            intervalKind: ScheduleIntervalKind(rawValue: cadence.rawValue) ?? .daily,
            intervalCount: 1,
            startDate: ISO8601DateFormatter().string(from: Date()),
            deliveryEmail: nil
        )
        let created = try await api.createExportSchedule(req)
        return ScheduledExport(
            id: String(created.id),
            cadence: cadence,
            destination: destination,
            lastRunAt: nil,
            nextRunAt: created.nextRunAt.flatMap { parseISO($0) }
        )
    }

    public func deleteSchedule(id: String) async throws {
        guard let intId = Int(id) else { return }
        try await api.cancelExportSchedule(id: intId)
    }

    // MARK: - Private helpers

    private func parseISO(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }
}
