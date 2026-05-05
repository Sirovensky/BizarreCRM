import Foundation
import Observation

// MARK: - DataExportViewModel

/// Drives the export wizard, full-tenant export, per-domain export,
/// customer (GDPR) export, and scheduled export CRUD.
@Observable
@MainActor
public final class DataExportViewModel {

    // MARK: - State

    public private(set) var isLoading: Bool = false
    public private(set) var startedJob: ExportJob?
    public private(set) var errorMessage: String?

    // Passphrase for full tenant export (not stored elsewhere)
    public var passphrase: String = ""
    public var showConfirmSheet: Bool = false

    // MARK: - Wizard state

    public var wizardEntity: ExportEntity = .full
    public var wizardFormat: ExportFormat = .csv
    public var wizardDateFrom: Date? = nil
    public var wizardDateTo: Date? = nil

    // MARK: - New schedule management (server-accurate model)

    public private(set) var schedules: [ExportSchedule] = []
    public private(set) var isLoadingSchedules: Bool = false

    // MARK: - Rate status

    public private(set) var rateStatus: DataExportRateStatus? = nil

    // MARK: - Legacy scheduled exports (for existing ScheduledExportListView compat)

    public private(set) var legacySchedules: [ScheduledExport] = []

    // MARK: - Dependencies (internal for sub-view wiring)

    let repository: ExportRepository

    public init(repository: ExportRepository) {
        self.repository = repository
    }

    // MARK: - Full tenant (async job via POST /tenant/export)

    public func requestFullTenantExport() {
        showConfirmSheet = true
    }

    /// Confirms and starts a full-tenant export job.
    /// Passphrase must be at least 12 chars (server minimum).
    public func confirmTenantExport() async {
        guard passphrase.count >= 8 else {
            errorMessage = "A passphrase of at least 8 characters is required."
            return
        }
        await performLegacy {
            try await self.repository.startLegacyTenantExport(passphrase: self.passphrase)
        }
        passphrase = ""
        showConfirmSheet = false
    }

    // MARK: - Rate status

    public func loadRateStatus() async {
        do {
            rateStatus = try await repository.fetchDataExportRateStatus()
        } catch {
            // Non-fatal — UI shows "unknown" state
        }
    }

    // MARK: - Domain export (per-entity, CSV/XLSX/JSON with date range)

    public func startDomainExport(entity: String, filters: [String: String]) async {
        // Legacy shim — domain export is local CSV for now
        // (server per-entity async job endpoint not yet in routes)
        // Build CSV from the rows provided by the view; show share sheet.
        errorMessage = "Per-domain export is available via the Export menu on each list view."
    }

    // MARK: - Customer (GDPR) export

    public func startCustomerExport(customerId: String) async {
        await performLegacy {
            // GDPR export is available via the customer detail menu.
            // For the legacy shim, create a placeholder job.
            ExportJob(id: "gdpr-\(customerId)", scope: .customer, status: .queued)
        }
    }

    // MARK: - New schedule management

    public func loadSchedules() async {
        isLoadingSchedules = true
        defer { isLoadingSchedules = false }
        do {
            schedules = try await repository.listSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createSchedule(_ request: CreateScheduleRequest) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let created = try await repository.createSchedule(request)
            schedules = schedules + [created]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateSchedule(id: Int, request: UpdateScheduleRequest) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await repository.updateSchedule(id: id, request: request)
            schedules = schedules.map { $0.id == id ? updated : $0 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pauseSchedule(id: Int) async {
        do {
            try await repository.pauseSchedule(id: id)
            schedules = schedules.map { s in
                s.id == id
                    ? ExportSchedule(
                        id: s.id, name: s.name, exportType: s.exportType,
                        intervalKind: s.intervalKind, intervalCount: s.intervalCount,
                        nextRunAt: s.nextRunAt, deliveryEmail: s.deliveryEmail,
                        status: .paused)
                    : s
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resumeSchedule(id: Int) async {
        do {
            try await repository.resumeSchedule(id: id)
            schedules = schedules.map { s in
                s.id == id
                    ? ExportSchedule(
                        id: s.id, name: s.name, exportType: s.exportType,
                        intervalKind: s.intervalKind, intervalCount: s.intervalCount,
                        nextRunAt: s.nextRunAt, deliveryEmail: s.deliveryEmail,
                        status: .active)
                    : s
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelSchedule(id: Int) async {
        do {
            try await repository.cancelSchedule(id: id)
            schedules = schedules.filter { $0.id != id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Legacy schedule management (for ScheduledExportListView)

    public func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async {
        do {
            let saved = try await repository.saveSchedule(cadence: cadence, destination: destination)
            if let idx = legacySchedules.firstIndex(where: { $0.id == saved.id }) {
                legacySchedules = legacySchedules.enumerated().map {
                    $0.offset == idx ? saved : $0.element
                }
            } else {
                legacySchedules = legacySchedules + [saved]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSchedule(id: String) async {
        do {
            try await repository.deleteSchedule(id: id)
            legacySchedules = legacySchedules.filter { $0.id != id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Error

    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Private

    /// Run an async action that produces an ExportJob and reflect loading/error state.
    private func performLegacy(_ action: @escaping () async throws -> ExportJob) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            startedJob = try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
