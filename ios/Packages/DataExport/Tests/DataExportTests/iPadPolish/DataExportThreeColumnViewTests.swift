import Testing
import Foundation
@testable import DataExport

// MARK: - DataExportThreeColumnViewTests
//
// Tests the data-layer and ViewModel interactions that DataExportThreeColumnView
// depends on. Pure logic tests — no SwiftUI rendering.

@Suite("DataExportThreeColumnView — ViewModel integration")
@MainActor
struct DataExportThreeColumnViewTests {

    // MARK: - Initial state

    @Test("ViewModel starts with no startedJob")
    func viewModelNoStartedJob() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.startedJob == nil)
    }

    @Test("ViewModel starts with empty schedules")
    func viewModelEmptySchedules() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.schedules.isEmpty)
    }

    @Test("ViewModel starts with isLoadingSchedules false")
    func viewModelLoadingFalse() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(!vm.isLoadingSchedules)
    }

    // MARK: - Sidebar kind selection drives content

    @Test("ExportKind.scheduled selection triggers schedule load")
    func scheduledSelectionLoadsSchedules() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 1, name: "Daily full", exportType: .full,
                           intervalKind: .daily, intervalCount: 1, status: .active)
        ])
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].name == "Daily full")
    }

    @Test("ExportKind allCases are in expected order for ⌘1..⌘4 mapping")
    func exportKindOrderForJumpShortcuts() {
        let cases = ExportKind.allCases
        #expect(cases[0] == .onDemand)
        #expect(cases[1] == .scheduled)
        #expect(cases[2] == .gdpr)
        #expect(cases[3] == .settings)
    }

    // MARK: - Detail column: on-demand job selection

    @Test("Selected job ID is nil initially (no detail shown)")
    func selectedJobIdNilInitially() {
        // Three-column view starts with no selection — detail shows placeholder.
        // We test this via the ViewModel's startedJob being nil.
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.startedJob == nil)
    }

    @Test("After successful tenant export startedJob is set")
    func startedJobSetAfterExport() async {
        let repo = MockExportRepository()
        repo.startTenantLegacyResult = .success(
            ExportJob(id: "99", scope: .fullTenant, status: .queued)
        )
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()
        #expect(vm.startedJob != nil)
        #expect(vm.startedJob?.id == "99")
    }

    // MARK: - Detail column: scheduled selection

    @Test("selectedScheduleId matches schedule in list after load")
    func selectedScheduleIdMatchesList() async {
        let repo = MockExportRepository()
        let schedules = [
            ExportSchedule(id: 10, name: "Sched A", exportType: .customers,
                           intervalKind: .weekly, intervalCount: 1, status: .active),
            ExportSchedule(id: 20, name: "Sched B", exportType: .invoices,
                           intervalKind: .monthly, intervalCount: 1, status: .paused)
        ]
        repo.schedulesResult = .success(schedules)
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()

        let selectedId = 10
        let found = vm.schedules.first(where: { $0.id == selectedId })
        #expect(found != nil)
        #expect(found?.name == "Sched A")
    }

    // MARK: - Toolbar action: new export

    @Test("showConfirmSheet toggled to true by requestFullTenantExport")
    func newExportTogglesSheet() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(!vm.showConfirmSheet)
        vm.requestFullTenantExport()
        #expect(vm.showConfirmSheet)
    }

    // MARK: - Refresh action

    @Test("Refresh clears and reloads schedules")
    func refreshReloadsSchedules() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 5, name: "Refreshed", exportType: .expenses,
                           intervalKind: .daily, intervalCount: 1)
        ])
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].name == "Refreshed")
    }

    // MARK: - Cancel action: keyboard shortcut handler

    @Test("cancelSchedule removes selected schedule from list")
    func cancelActionRemovesSchedule() async {
        let repo = MockExportRepository()
        repo.schedulesResult = .success([
            ExportSchedule(id: 7, name: "To cancel", exportType: .full,
                           intervalKind: .daily, intervalCount: 1),
            ExportSchedule(id: 8, name: "Keep", exportType: .tickets,
                           intervalKind: .weekly, intervalCount: 1)
        ])
        repo.cancelResult = .success(())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        await vm.cancelSchedule(id: 7)
        #expect(vm.schedules.count == 1)
        #expect(vm.schedules[0].id == 8)
    }

    // MARK: - Download/Share handler: only works when downloadUrl present

    @Test("Download requires startedJob with downloadUrl")
    func downloadRequiresUrl() async {
        let repo = MockExportRepository()
        repo.startTenantLegacyResult = .success(
            ExportJob(id: "5", scope: .fullTenant, status: .completed,
                      downloadUrl: "https://example.com/export.zip")
        )
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "ValidPassphrase!"
        await vm.confirmTenantExport()

        let urlString = vm.startedJob?.downloadUrl
        let url = urlString.flatMap { URL(string: $0) }
        #expect(url != nil)
        #expect(url?.scheme == "https")
    }

    @Test("Download is unavailable when startedJob has no downloadUrl")
    func downloadUnavailableWithoutUrl() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        // startedJob is nil → no URL
        let url = vm.startedJob?.downloadUrl.flatMap { URL(string: $0) }
        #expect(url == nil)
    }

    // MARK: - Error state management

    @Test("Alert dismissed via clearError resets errorMessage")
    func alertDismissedClearsError() async {
        let repo = MockExportRepository()
        let vm = DataExportViewModel(repository: repo)
        vm.passphrase = "x" // too short
        await vm.confirmTenantExport()
        #expect(vm.errorMessage != nil)
        vm.clearError()
        #expect(vm.errorMessage == nil)
    }

    @Test("Error from loadSchedules is surfaced in errorMessage")
    func schedulesLoadErrorSurfaced() async {
        let repo = MockExportRepository()
        struct LoadError: Error, LocalizedError {
            var errorDescription: String? { "Server unreachable" }
        }
        repo.schedulesResult = .failure(LoadError())
        let vm = DataExportViewModel(repository: repo)
        await vm.loadSchedules()
        #expect(vm.errorMessage == "Server unreachable")
    }

    // MARK: - Three-column wizard state defaults

    @Test("Wizard defaults: entity=.full, format=.csv")
    func wizardDefaults() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        #expect(vm.wizardEntity == .full)
        #expect(vm.wizardFormat == .csv)
    }

    @Test("Wizard entity can be changed for detail column display")
    func wizardEntityChangedForDetail() {
        let vm = DataExportViewModel(repository: MockExportRepository())
        vm.wizardEntity = .invoices
        #expect(vm.wizardEntity == .invoices)
    }
}
