import Testing
import Foundation
@testable import DataExport

// MARK: - DataExportViewModelTests

@Suite("DataExportViewModel — export initiation and schedule management")
@MainActor
struct DataExportViewModelTests {

    // MARK: - Full tenant export (legacy ExportJob shim)

    @Test("confirmTenantExport fails with empty passphrase")
    func confirmTenantExportEmptyPassphrase() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = ""
        await vm.confirmTenantExport()
        #expect(vm.errorMessage != nil)
        #expect(vm.startedJob == nil)
    }

    @Test("confirmTenantExport fails with short passphrase")
    func confirmTenantExportShortPassphrase() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "short"
        await vm.confirmTenantExport()
        #expect(vm.errorMessage != nil)
        #expect(vm.startedJob == nil)
    }

    @Test("confirmTenantExport succeeds with valid passphrase")
    func confirmTenantExportSuccess() async {
        let repo = MockExportRepository()
        repo.startTenantLegacyResult = .success(ExportJob(id: "j-1", scope: .fullTenant, status: .queued))
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "SecurePass123"
        await vm.confirmTenantExport()
        #expect(vm.errorMessage == nil)
        #expect(vm.startedJob != nil)
        #expect(vm.startedJob?.scope == .fullTenant)
    }

    @Test("confirmTenantExport clears passphrase on success")
    func passphraseCleared() async {
        let repo = MockExportRepository()
        repo.startTenantLegacyResult = .success(ExportJob(id: "j-2", scope: .fullTenant, status: .queued))
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(vm.passphrase.isEmpty)
    }

    @Test("confirmTenantExport dismisses sheet on success")
    func confirmSheetDismissed() async {
        let repo = MockExportRepository()
        repo.startTenantLegacyResult = .success(ExportJob(id: "j-3", scope: .fullTenant, status: .queued))
        let vm = DataExportViewModel(repository: repo)
        vm.showConfirmSheet = true
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(!vm.showConfirmSheet)
    }

    @Test("requestFullTenantExport sets showConfirmSheet")
    func requestSetsShowConfirm() {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        #expect(!vm.showConfirmSheet)
        vm.requestFullTenantExport()
        #expect(vm.showConfirmSheet)
    }

    @Test("confirmTenantExport sets error on repository failure")
    func tenantExportRepositoryFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Timeout" }
        }
        repo.startTenantLegacyResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(vm.errorMessage == "Timeout")
        #expect(vm.startedJob == nil)
    }

    // MARK: - Rate status

    @Test("loadRateStatus sets rateStatus on success")
    func loadRateStatus() async {
        let repo = MockExportRepository()
        repo.rateStatusResult = .success(
            DataExportRateStatus(lastExportAt: "2026-04-23T00:00:00Z", nextAllowedInSeconds: 0, allowed: true, rateLimitWindowSeconds: 3600)
        )
        let vm = DataExportViewModel(repository: repo)
        await vm.loadRateStatus()
        #expect(vm.rateStatus != nil)
        #expect(vm.rateStatus?.allowed == true)
    }

    @Test("loadRateStatus does not set error on failure (non-fatal)")
    func loadRateStatusFailureSilent() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Network" }
        }
        repo.rateStatusResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadRateStatus()
        #expect(vm.rateStatus == nil)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - New schedule management

    @Test("loadSchedules populates schedules array")
    func loadSchedules() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 1, name: "Daily backup", exportType: .full, intervalKind: .daily, intervalCount: 1),
            ExportSchedule(id: 2, name: "Weekly tickets", exportType: .tickets, intervalKind: .weekly, intervalCount: 1)
        ])
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(vm.schedules.count == 2)
    }

    @Test("loadSchedules sets errorMessage on failure")
    func loadSchedulesFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Cannot load" }
        }
        repo.schedulesResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(vm.errorMessage == "Cannot load")
    }

    @Test("createSchedule appends to schedules")
    func createScheduleAppends() async {
        let repo = MockExportRepository()
        repo.createScheduleResult = .success(
            ExportSchedule(id: 10, name: "New export", exportType: .customers, intervalKind: .daily, intervalCount: 1)
        )
        let vm = DataExportViewModel(repository: repo)
        let req = CreateScheduleRequest(
            name: "New export", exportType: .customers,
            intervalKind: .daily, intervalCount: 1,
            startDate: "2026-04-23T00:00:00Z"
        )
        await vm.createSchedule(req)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].id == 10)
        #expect(vm.schedules[0].name == "New export")
    }

    @Test("createSchedule sets errorMessage on failure")
    func createScheduleFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Create failed" }
        }
        repo.createScheduleResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        let req = CreateScheduleRequest(
            name: "Bad", exportType: .full,
            intervalKind: .daily, intervalCount: 1,
            startDate: "2026-04-23T00:00:00Z"
        )
        await vm.createSchedule(req)
        #expect(vm.errorMessage == "Create failed")
    }

    @Test("updateSchedule replaces existing schedule by id (immutable)")
    func updateScheduleReplaces() async {
        let repo = MockExportRepository()
        let existing = ExportSchedule(id: 5, name: "Old name", exportType: .full, intervalKind: .daily, intervalCount: 1)
        repo.schedulesResult = .success([existing])
        repo.updateScheduleResult = .success(
            ExportSchedule(id: 5, name: "Updated name", exportType: .full, intervalKind: .weekly, intervalCount: 2)
        )
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        let req = UpdateScheduleRequest(name: "Updated name", intervalKind: .weekly, intervalCount: 2)
        await vm.updateSchedule(id: 5, request: req)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].name == "Updated name")
        #expect(vm.schedules[0].intervalKind == .weekly)
    }

    @Test("pauseSchedule sets schedule status to paused (optimistic)")
    func pauseSchedule() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 3, name: "Daily", exportType: .full, intervalKind: .daily, intervalCount: 1, status: .active)
        ])
        repo.pauseResumeResult = .success(())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.pauseSchedule(id: 3)
        #expect(vm.schedules[0].status == .paused)
    }

    @Test("resumeSchedule sets schedule status to active (optimistic)")
    func resumeSchedule() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 4, name: "Weekly", exportType: .invoices, intervalKind: .weekly, intervalCount: 1, status: .paused)
        ])
        repo.pauseResumeResult = .success(())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.resumeSchedule(id: 4)
        #expect(vm.schedules[0].status == .active)
    }

    @Test("cancelSchedule removes schedule from array")
    func cancelScheduleRemoves() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 1, name: "A", exportType: .full, intervalKind: .daily, intervalCount: 1),
            ExportSchedule(id: 2, name: "B", exportType: .tickets, intervalKind: .daily, intervalCount: 1)
        ])
        repo.cancelResult = .success(())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.cancelSchedule(id: 1)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].id == 2)
    }

    @Test("cancelSchedule sets errorMessage on failure")
    func cancelScheduleFailure() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 9, name: "Fail", exportType: .full, intervalKind: .daily, intervalCount: 1)
        ])
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Cancel failed" }
        }
        repo.cancelResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.cancelSchedule(id: 9)
        #expect(vm.errorMessage == "Cancel failed")
    }

    // MARK: - Wizard state

    @Test("wizardEntity defaults to .full")
    func wizardEntityDefault() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.wizardEntity == .full)
    }

    @Test("wizardFormat defaults to .csv")
    func wizardFormatDefault() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.wizardFormat == .csv)
    }

    @Test("wizardEntity can be changed")
    func wizardEntityCanBeChanged() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        vm.wizardEntity = .customers
        #expect(vm.wizardEntity == .customers)
    }

    @Test("wizardDateFrom and wizardDateTo are nil by default")
    func wizardDatesNilByDefault() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.wizardDateFrom == nil)
        #expect(vm.wizardDateTo == nil)
    }

    @Test("wizardFormat can be changed to .json")
    func wizardFormatCanBeChanged() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        vm.wizardFormat = .json
        #expect(vm.wizardFormat == .json)
    }

    // MARK: - clearError

    @Test("clearError resets errorMessage to nil")
    func clearError() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "short"
        await vm.confirmTenantExport()
        #expect(vm.errorMessage != nil)
        vm.clearError()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - isLoadingSchedules lifecycle

    @Test("isLoadingSchedules is false after load completes")
    func isLoadingSchedulesFalseAfter() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(!vm.isLoadingSchedules)
    }

    @Test("isLoadingSchedules is false after load failure")
    func isLoadingSchedulesFalseAfterFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "fail" }
        }
        repo.schedulesResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(!vm.isLoadingSchedules)
    }
}
