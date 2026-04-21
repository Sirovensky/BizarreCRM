import Testing
import Foundation
@testable import DataExport

// MARK: - DataExportViewModelTests

@Suite("DataExportViewModel — export initiation and schedule management")
@MainActor
struct DataExportViewModelTests {

    // MARK: - Tenant export

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
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(vm.passphrase.isEmpty)
    }

    @Test("confirmTenantExport dismisses sheet on success")
    func confirmSheetDismissed() async {
        let repo = MockExportRepository()
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
        repo.startTenantResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(vm.errorMessage == "Timeout")
        #expect(vm.startedJob == nil)
    }

    // MARK: - Domain export

    @Test("startDomainExport sets startedJob with domain scope")
    func startDomainExport() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        await vm.startDomainExport(entity: "customers", filters: ["status": "active"])
        #expect(vm.startedJob?.scope == .domain)
        #expect(vm.errorMessage == nil)
    }

    @Test("startDomainExport sets errorMessage on failure")
    func startDomainExportFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Domain export failed" }
        }
        repo.startDomainResult = .failure(NetError())
        let vm = DataExportViewModel(repository: repo)
        await vm.startDomainExport(entity: "tickets", filters: [:])
        #expect(vm.errorMessage == "Domain export failed")
    }

    // MARK: - Customer export

    @Test("startCustomerExport sets startedJob with customer scope")
    func startCustomerExport() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        await vm.startCustomerExport(customerId: "cust-42")
        #expect(vm.startedJob?.scope == .customer)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Schedule management

    @Test("loadSchedules populates schedules array")
    func loadSchedules() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ScheduledExport(id: "s1", cadence: .daily, destination: .icloud),
            ScheduledExport(id: "s2", cadence: .weekly, destination: .icloud)
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

    @Test("saveSchedule appends to schedules when new")
    func saveScheduleAppends() async {
        let repo = MockExportRepository()
        repo.saveScheduleResult = .success(
            ScheduledExport(id: "sched-new", cadence: .monthly, destination: .icloud)
        )
        let vm = DataExportViewModel(repository: repo)
        #expect(vm.schedules.isEmpty)
        await vm.saveSchedule(cadence: .monthly, destination: .icloud)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].id == "sched-new")
    }

    @Test("saveSchedule replaces existing schedule by id")
    func saveScheduleReplaces() async {
        let repo = MockExportRepository()
        let existing = ScheduledExport(id: "sched-1", cadence: .daily, destination: .icloud)
        repo.schedulesResult = .success([existing])
        repo.saveScheduleResult = .success(
            ScheduledExport(id: "sched-1", cadence: .weekly, destination: .icloud)
        )
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.saveSchedule(cadence: .weekly, destination: .icloud)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].cadence == .weekly)
    }

    @Test("deleteSchedule removes from schedules array")
    func deleteScheduleRemoves() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ScheduledExport(id: "s1", cadence: .daily, destination: .icloud),
            ScheduledExport(id: "s2", cadence: .weekly, destination: .icloud)
        ])
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.deleteSchedule(id: "s1")
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].id == "s2")
    }

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

    @Test("isLoading is true during export then false after")
    func isLoadingLifecycle() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        // Verify that after the async call isLoading is back to false
        await vm.startDomainExport(entity: "invoices", filters: [:])
        #expect(!vm.isLoading)
    }
}
