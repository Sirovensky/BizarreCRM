import Testing
import Foundation
@testable import DataExport

// MARK: - SettingsExportViewModelTests

@Suite("SettingsExportViewModel — settings backup, restore, and templates")
@MainActor
struct SettingsExportViewModelTests {

    // MARK: - Export

    @Test("exportSettings sets exportedPayload on success")
    func exportSuccess() async {
        let repo = MockExportRepository()
        repo.settingsExportResult = .success(
            SettingsExportPayload(exportedAt: "2026-04-23T10:00:00Z", version: 1, settings: ["store_name": "My Shop", "store_timezone": "UTC"])
        )
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        #expect(vm.exportedPayload != nil)
        #expect(vm.exportedPayload?.settings["store_name"] == "My Shop")
        #expect(vm.errorMessage == nil)
    }

    @Test("exportSettings sets successMessage on success")
    func exportSetsSuccessMessage() async {
        let repo = MockExportRepository()
        repo.settingsExportResult = .success(
            SettingsExportPayload(exportedAt: "2026-04-23T10:00:00Z", version: 1, settings: ["store_name": "X"])
        )
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        #expect(vm.successMessage != nil)
    }

    @Test("exportSettings sets errorMessage on failure")
    func exportFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Export error" }
        }
        repo.settingsExportResult = .failure(NetError())
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        #expect(vm.errorMessage == "Export error")
        #expect(vm.exportedPayload == nil)
    }

    @Test("isExporting is false after export completes")
    func isExportingFalseAfter() async {
        let repo = MockExportRepository()
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        #expect(!vm.isExporting)
    }

    @Test("exportedJSON returns valid JSON string")
    func exportedJSONValid() async {
        let repo = MockExportRepository()
        repo.settingsExportResult = .success(
            SettingsExportPayload(exportedAt: "2026-04-23T10:00:00Z", version: 1, settings: ["store_name": "Test"])
        )
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        let json = vm.exportedJSON()
        #expect(json != nil)
        #expect(json!.contains("store_name"))
        #expect(json!.contains("Test"))
    }

    @Test("exportedJSON returns nil when no payload")
    func exportedJSONNilWhenNoPayload() {
        let vm = SettingsExportViewModel(repository: MockExportRepository())
        #expect(vm.exportedJSON() == nil)
    }

    // MARK: - Import

    @Test("importSettings fails with empty importText")
    func importEmptyText() async {
        let repo = MockExportRepository()
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = ""
        await vm.importSettings()
        #expect(vm.errorMessage != nil)
        #expect(vm.importResult == nil)
    }

    @Test("importSettings fails with invalid JSON")
    func importInvalidJSON() async {
        let repo = MockExportRepository()
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = "not valid json at all {{{{"
        await vm.importSettings()
        #expect(vm.errorMessage != nil)
    }

    @Test("importSettings succeeds with valid SettingsExportPayload JSON")
    func importValidPayload() async {
        let repo = MockExportRepository()
        repo.settingsImportResult = .success(SettingsImportResult(imported: 2, skipped: [], total: 2))
        let vm = SettingsExportViewModel(repository: repo)
        let json = """
        {
          "exported_at": "2026-04-23T00:00:00Z",
          "version": 1,
          "settings": { "store_name": "Shop A", "store_email": "shop@example.com" }
        }
        """
        vm.importText = json
        await vm.importSettings()
        #expect(vm.importResult != nil)
        #expect(vm.importResult?.imported == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test("importSettings succeeds with flat JSON object")
    func importFlatJSON() async {
        let repo = MockExportRepository()
        repo.settingsImportResult = .success(SettingsImportResult(imported: 1, skipped: [], total: 1))
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = """{"store_name": "Flat Shop"}"""
        await vm.importSettings()
        #expect(vm.importResult?.imported == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("importSettings sets successMessage on success")
    func importSetsSuccessMessage() async {
        let repo = MockExportRepository()
        repo.settingsImportResult = .success(SettingsImportResult(imported: 3, skipped: ["bad_key"], total: 4))
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = """{"store_name": "X", "store_email": "y@z.com", "store_phone": "555"}"""
        await vm.importSettings()
        #expect(vm.successMessage != nil)
    }

    @Test("importSettings clears importText on success")
    func importClearsText() async {
        let repo = MockExportRepository()
        repo.settingsImportResult = .success(SettingsImportResult(imported: 1, skipped: [], total: 1))
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = """{"store_name": "X"}"""
        await vm.importSettings()
        #expect(vm.importText.isEmpty)
    }

    @Test("importSettings sets errorMessage on repository failure")
    func importRepositoryFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Import failed" }
        }
        repo.settingsImportResult = .failure(NetError())
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = """{"store_name": "X"}"""
        await vm.importSettings()
        #expect(vm.errorMessage == "Import failed")
    }

    @Test("isImporting is false after import completes")
    func isImportingFalseAfter() async {
        let repo = MockExportRepository()
        repo.settingsImportResult = .success(SettingsImportResult(imported: 1, skipped: [], total: 1))
        let vm = SettingsExportViewModel(repository: repo)
        vm.importText = """{"store_name": "X"}"""
        await vm.importSettings()
        #expect(!vm.isImporting)
    }

    // MARK: - Templates

    @Test("loadTemplates populates templates array")
    func loadTemplates() async {
        let repo = MockExportRepository()
        repo.templatesResult = .success([
            ShopTemplate(id: "phone_repair", label: "Phone Repair", description: "Phone defaults", settingsCount: 10),
            ShopTemplate(id: "computer_repair", label: "Computer Repair", description: "Computer defaults", settingsCount: 8)
        ])
        let vm = SettingsExportViewModel(repository: repo)
        await vm.loadTemplates()
        #expect(vm.templates.count == 2)
        #expect(vm.templates[0].id == "phone_repair")
    }

    @Test("loadTemplates sets errorMessage on failure")
    func loadTemplatesFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Templates unavailable" }
        }
        repo.templatesResult = .failure(NetError())
        let vm = SettingsExportViewModel(repository: repo)
        await vm.loadTemplates()
        #expect(vm.errorMessage == "Templates unavailable")
    }

    @Test("applyTemplate sets successMessage on success")
    func applyTemplateSuccess() async {
        let repo = MockExportRepository()
        repo.applyTemplateResult = .success(())
        let vm = SettingsExportViewModel(repository: repo)
        await vm.applyTemplate(id: "phone_repair")
        #expect(vm.successMessage == "Template applied")
        #expect(vm.errorMessage == nil)
    }

    @Test("applyTemplate sets errorMessage on failure")
    func applyTemplateFailure() async {
        let repo = MockExportRepository()
        struct NetError: Error, LocalizedError {
            var errorDescription: String? { "Template not found" }
        }
        repo.applyTemplateResult = .failure(NetError())
        let vm = SettingsExportViewModel(repository: repo)
        await vm.applyTemplate(id: "unknown_template")
        #expect(vm.errorMessage == "Template not found")
    }

    @Test("isApplyingTemplate is false after apply completes")
    func isApplyingTemplateFalseAfter() async {
        let repo = MockExportRepository()
        let vm = SettingsExportViewModel(repository: repo)
        await vm.applyTemplate(id: "phone_repair")
        #expect(!vm.isApplyingTemplate)
    }

    // MARK: - clearMessages

    @Test("clearMessages resets errorMessage and successMessage")
    func clearMessages() async {
        let repo = MockExportRepository()
        repo.settingsExportResult = .success(
            SettingsExportPayload(exportedAt: "2026-04-23T00:00:00Z", version: 1, settings: [:])
        )
        let vm = SettingsExportViewModel(repository: repo)
        await vm.exportSettings()
        #expect(vm.successMessage != nil)
        vm.clearMessages()
        #expect(vm.successMessage == nil)
        #expect(vm.errorMessage == nil)
    }
}
