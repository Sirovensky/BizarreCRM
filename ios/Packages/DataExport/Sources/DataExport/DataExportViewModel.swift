import Foundation
import Observation

// MARK: - DataExportViewModel

/// Drives full-tenant, per-domain, and customer export initiation.
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

    // MARK: - Scheduled exports

    public private(set) var schedules: [ScheduledExport] = []
    public private(set) var isLoadingSchedules: Bool = false

    // MARK: - Dependencies (internal for sub-view wiring)

    let repository: ExportRepository

    public init(repository: ExportRepository) {
        self.repository = repository
    }

    // MARK: - Full tenant

    public func requestFullTenantExport() {
        showConfirmSheet = true
    }

    public func confirmTenantExport() async {
        guard passphrase.count >= 8 else {
            errorMessage = "A passphrase of at least 8 characters is required."
            return
        }
        await perform {
            try await self.repository.startTenantExport(passphrase: self.passphrase)
        }
        passphrase = ""
        showConfirmSheet = false
    }

    // MARK: - Domain export

    public func startDomainExport(entity: String, filters: [String: String]) async {
        await perform {
            try await self.repository.startDomainExport(entity: entity, filters: filters)
        }
    }

    // MARK: - Customer (GDPR) export

    public func startCustomerExport(customerId: String) async {
        await perform {
            try await self.repository.startCustomerExport(customerId: customerId)
        }
    }

    // MARK: - Schedules

    public func loadSchedules() async {
        isLoadingSchedules = true
        defer { isLoadingSchedules = false }
        do {
            schedules = try await repository.listSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async {
        do {
            let saved = try await repository.saveSchedule(cadence: cadence, destination: destination)
            // Immutable update — replace existing or append
            if let idx = schedules.firstIndex(where: { $0.id == saved.id }) {
                schedules = schedules.enumerated().map { $0.offset == idx ? saved : $0.element }
            } else {
                schedules = schedules + [saved]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSchedule(id: String) async {
        do {
            try await repository.deleteSchedule(id: id)
            schedules = schedules.filter { $0.id != id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func perform(_ action: @escaping () async throws -> ExportJob) async {
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
