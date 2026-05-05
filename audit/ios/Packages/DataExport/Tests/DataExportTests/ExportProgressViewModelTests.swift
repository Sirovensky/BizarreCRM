import Testing
import Foundation
@testable import DataExport

// MARK: - MockExportRepository
// Shared mock for all DataExport test suites. Implements the full ExportRepository
// protocol so every VM can be tested in isolation via result stubs.

final class MockExportRepository: ExportRepository, @unchecked Sendable {

    // MARK: - Tenant async job stubs

    var startTenantResult: Result<TenantExportJob, Error> = .success(
        TenantExportJob(id: 1, status: .queued)
    )
    var pollTenantResult: Result<TenantExportJob, Error> = .success(
        TenantExportJob(id: 1, status: .completed)
    )
    var rateStatusResult: Result<DataExportRateStatus, Error> = .success(
        DataExportRateStatus(lastExportAt: nil, nextAllowedInSeconds: 0, allowed: true, rateLimitWindowSeconds: 3600)
    )

    // MARK: - Legacy ExportJob shim stubs (ExportProgressViewModel)

    var startTenantLegacyResult: Result<ExportJob, Error> = .success(
        ExportJob(id: "job-1", scope: .fullTenant, status: .queued)
    )
    /// Queue of sequential poll responses for ExportProgressViewModel tests.
    var pollQueue: [Result<ExportJob, Error>] = []
    private var pollIndex = 0

    // MARK: - GDPR stub

    var eraseResult: Result<Void, Error> = .success(())

    // MARK: - Schedule CRUD stubs

    var schedulesResult: Result<[ExportSchedule], Error> = .success([])
    var scheduleDetailResult: Result<ScheduleDetail, Error> = .success(
        ScheduleDetail(
            schedule: ExportSchedule(id: 1, name: "Detail", exportType: .full, intervalKind: .daily, intervalCount: 1),
            recentRuns: []
        )
    )
    var createScheduleResult: Result<ExportSchedule, Error> = .success(
        ExportSchedule(id: 99, name: "Created", exportType: .full, intervalKind: .daily, intervalCount: 1)
    )
    var updateScheduleResult: Result<ExportSchedule, Error> = .success(
        ExportSchedule(id: 99, name: "Updated", exportType: .full, intervalKind: .weekly, intervalCount: 1)
    )
    var pauseResumeResult: Result<Void, Error> = .success(())
    var cancelResult: Result<Void, Error> = .success(())

    // MARK: - Settings export / import stubs

    var settingsExportResult: Result<SettingsExportPayload, Error> = .success(
        SettingsExportPayload(exportedAt: "2026-04-23T00:00:00Z", version: 1, settings: [:])
    )
    var settingsImportResult: Result<SettingsImportResult, Error> = .success(
        SettingsImportResult(imported: 0, skipped: [], total: 0)
    )
    var templatesResult: Result<[ShopTemplate], Error> = .success([])
    var applyTemplateResult: Result<Void, Error> = .success(())

    // MARK: - Legacy ScheduledExport stubs

    var legacySchedulesResult: Result<[ScheduledExport], Error> = .success([])
    var saveScheduleResult: Result<ScheduledExport, Error> = .success(
        ScheduledExport(id: "sched-1", cadence: .daily, destination: .icloud)
    )

    // MARK: - ExportRepository: tenant async job

    func startTenantExport(passphrase: String) async throws -> TenantExportJob {
        try startTenantResult.get()
    }

    func pollTenantExport(jobId: Int) async throws -> TenantExportJob {
        try pollTenantResult.get()
    }

    func fetchDataExportRateStatus() async throws -> DataExportRateStatus {
        try rateStatusResult.get()
    }

    // MARK: - ExportRepository: GDPR

    func eraseCustomerPII(customerId: Int, confirmName: String) async throws {
        try eraseResult.get()
    }

    // MARK: - ExportRepository: schedule CRUD

    func listSchedules() async throws -> [ExportSchedule] {
        try schedulesResult.get()
    }

    func getSchedule(id: Int) async throws -> ScheduleDetail {
        try scheduleDetailResult.get()
    }

    func createSchedule(_ request: CreateScheduleRequest) async throws -> ExportSchedule {
        try createScheduleResult.get()
    }

    func updateSchedule(id: Int, request: UpdateScheduleRequest) async throws -> ExportSchedule {
        try updateScheduleResult.get()
    }

    func pauseSchedule(id: Int) async throws { try pauseResumeResult.get() }
    func resumeSchedule(id: Int) async throws { try pauseResumeResult.get() }
    func cancelSchedule(id: Int) async throws { try cancelResult.get() }

    // MARK: - ExportRepository: settings export / import

    func fetchSettingsExport() async throws -> SettingsExportPayload {
        try settingsExportResult.get()
    }

    func importSettings(payload: [String: String]) async throws -> SettingsImportResult {
        try settingsImportResult.get()
    }

    func fetchShopTemplates() async throws -> [ShopTemplate] {
        try templatesResult.get()
    }

    func applyShopTemplate(id: String) async throws {
        try applyTemplateResult.get()
    }

    // MARK: - ExportRepository: legacy ExportJob shim

    func startLegacyTenantExport(passphrase: String) async throws -> ExportJob {
        try startTenantLegacyResult.get()
    }

    func pollExport(id: String) async throws -> ExportJob {
        guard pollIndex < pollQueue.count else {
            return ExportJob(id: id, scope: .fullTenant, status: .completed, progressPct: 1.0)
        }
        let result = pollQueue[pollIndex]
        pollIndex += 1
        return try result.get()
    }

    func getErrors(id: String) async throws -> [ExportError] { [] }

    func listLegacySchedules() async throws -> [ScheduledExport] {
        try legacySchedulesResult.get()
    }

    func saveSchedule(cadence: ExportCadence, destination: ExportDestination) async throws -> ScheduledExport {
        try saveScheduleResult.get()
    }

    func deleteSchedule(id: String) async throws {}
}

// MARK: - ExportProgressViewModelTests

@Suite("ExportProgressViewModel — status transitions and polling")
@MainActor
struct ExportProgressViewModelTests {

    // MARK: - Status transitions

    @Test("Initial job status reflects constructor argument")
    func initialStatus() async {
        let repo = MockExportRepository()
        let job = ExportJob(id: "j1", scope: .fullTenant, status: .preparing, progressPct: 0.1)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))
        #expect(vm.job.status == .preparing)
        #expect(vm.job.progressPct == 0.1)
    }

    @Test("Poll updates status from queued → completed")
    func pollStatusTransition() async throws {
        let repo = MockExportRepository()
        repo.pollQueue = [
            .success(ExportJob(id: "j1", scope: .fullTenant, status: .exporting, progressPct: 0.5)),
            .success(ExportJob(id: "j1", scope: .fullTenant, status: .completed, progressPct: 1.0, downloadUrl: "https://example.com/file.zip"))
        ]
        let job = ExportJob(id: "j1", scope: .fullTenant, status: .queued)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        // Give poll loop time to run two cycles
        try await Task.sleep(for: .milliseconds(100))
        vm.stopPolling()

        #expect(vm.job.status == .completed)
        #expect(vm.job.downloadUrl == "https://example.com/file.zip")
    }

    @Test("Scope is preserved across polls")
    func scopePreservedAcrossPolls() async throws {
        let repo = MockExportRepository()
        repo.pollQueue = [
            .success(ExportJob(id: "j2", scope: .fullTenant, status: .completed, progressPct: 1.0))
        ]
        let job = ExportJob(id: "j2", scope: .customer, status: .preparing)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(50))
        vm.stopPolling()

        // scope must stay .customer, not overwritten by poll's .fullTenant placeholder
        #expect(vm.job.scope == .customer)
    }

    @Test("Polling stops when status reaches completed")
    func pollingStopsOnTerminal() async throws {
        let repo = MockExportRepository()
        // pollQueue empty → returns .completed immediately on first poll
        let job = ExportJob(id: "j3", scope: .fullTenant, status: .queued)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(80))

        #expect(!vm.isPolling)
        #expect(vm.job.status == .completed)
    }

    @Test("stopPolling cancels the task")
    func stopPollingCancels() async throws {
        let repo = MockExportRepository()
        // Provide many long-running polls
        repo.pollQueue = (0..<10).map { _ in
            Result<ExportJob, Error>.success(
                ExportJob(id: "j4", scope: .fullTenant, status: .exporting, progressPct: 0.4)
            )
        }
        let job = ExportJob(id: "j4", scope: .fullTenant, status: .queued)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(50))

        vm.startPolling()
        #expect(vm.isPolling)

        vm.stopPolling()
        #expect(!vm.isPolling)
    }

    @Test("Poll error sets errorMessage and stops polling")
    func pollErrorSetsMessage() async throws {
        let repo = MockExportRepository()
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Network failure" }
        }
        repo.pollQueue = [.failure(FakeError())]
        let job = ExportJob(id: "j5", scope: .fullTenant, status: .queued)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(80))

        #expect(vm.errorMessage == "Network failure")
        #expect(!vm.isPolling)
    }

    @Test("startPolling is no-op for completed jobs")
    func startPollingNoOpForCompleted() async throws {
        let repo = MockExportRepository()
        let job = ExportJob(id: "j6", scope: .fullTenant, status: .completed, progressPct: 1.0)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(30))

        // Should never have started polling
        #expect(!vm.isPolling)
    }

    @Test("startPolling is no-op for failed jobs")
    func startPollingNoOpForFailed() async throws {
        let repo = MockExportRepository()
        let job = ExportJob(id: "j7", scope: .fullTenant, status: .failed)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!vm.isPolling)
    }

    @Test("progressPct is updated from poll response")
    func progressPctUpdated() async throws {
        let repo = MockExportRepository()
        repo.pollQueue = [
            .success(ExportJob(id: "j8", scope: .fullTenant, status: .exporting, progressPct: 0.65))
        ]
        let job = ExportJob(id: "j8", scope: .fullTenant, status: .queued, progressPct: 0.0)
        let vm = ExportProgressViewModel(job: job, repository: repo, pollInterval: .milliseconds(10))

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(60))
        vm.stopPolling()

        #expect(vm.job.progressPct >= 0.65)
    }
}
