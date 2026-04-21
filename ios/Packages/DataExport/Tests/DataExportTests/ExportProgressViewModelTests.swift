import Testing
import Foundation
@testable import DataExport

// MARK: - MockExportRepository

final class MockExportRepository: ExportRepository, @unchecked Sendable {
    var startTenantResult: Result<ExportJob, Error> = .success(
        ExportJob(id: "job-1", scope: .fullTenant, status: .queued)
    )
    var startDomainResult: Result<ExportJob, Error> = .success(
        ExportJob(id: "job-2", scope: .domain, status: .queued)
    )
    var startCustomerResult: Result<ExportJob, Error> = .success(
        ExportJob(id: "job-3", scope: .customer, status: .queued)
    )

    // Queue of poll responses to return in sequence
    var pollQueue: [Result<ExportJob, Error>] = []
    private var pollIndex = 0

    var errorsResult: Result<[ExportError], Error> = .success([])
    var schedulesResult: Result<[ScheduledExport], Error> = .success([])
    var saveScheduleResult: Result<ScheduledExport, Error> = .success(
        ScheduledExport(id: "sched-1", cadence: .daily, destination: .icloud)
    )

    func startTenantExport(passphrase: String) async throws -> ExportJob {
        try startTenantResult.get()
    }
    func startDomainExport(entity: String, filters: [String: String]) async throws -> ExportJob {
        try startDomainResult.get()
    }
    func startCustomerExport(customerId: String) async throws -> ExportJob {
        try startCustomerResult.get()
    }
    func pollExport(id: String) async throws -> ExportJob {
        guard pollIndex < pollQueue.count else {
            return ExportJob(id: id, scope: .fullTenant, status: .completed, progressPct: 1.0)
        }
        let result = pollQueue[pollIndex]
        pollIndex += 1
        return try result.get()
    }
    func getErrors(id: String) async throws -> [ExportError] { try errorsResult.get() }
    func listSchedules() async throws -> [ScheduledExport] { try schedulesResult.get() }
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
