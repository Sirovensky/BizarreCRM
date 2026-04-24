import XCTest
@testable import DataImport

// MARK: - DataImportKeyboardShortcutsTests

final class DataImportKeyboardShortcutsTests: XCTestCase {

    // MARK: - Shortcut definitions

    func test_allShortcuts_nonEmpty() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        XCTAssertFalse(shortcuts.isEmpty)
    }

    func test_allShortcuts_uniqueIDs() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        let ids = shortcuts.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Shortcut IDs must be unique")
    }

    func test_allShortcuts_nonEmptyDescriptions() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        for shortcut in shortcuts {
            XCTAssertFalse(shortcut.description.isEmpty, "Shortcut \(shortcut.key) has no description")
            XCTAssertFalse(shortcut.key.isEmpty, "Shortcut has empty key")
            XCTAssertFalse(shortcut.modifiers.isEmpty, "Shortcut has empty modifiers")
        }
    }

    func test_shortcutEntry_identifiableByKeyPlusModifiers() {
        let entry = KeyboardShortcutHelpEntry(key: "R", modifiers: "⌘", description: "Retry")
        XCTAssertEqual(entry.id, "R⌘")
    }

    func test_shortcutsContainAdvance() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        let hasAdvance = shortcuts.contains { $0.description.lowercased().contains("advance") || $0.description.lowercased().contains("next") }
        XCTAssertTrue(hasAdvance, "Expected an 'advance' / 'next step' shortcut")
    }

    func test_shortcutsContainCancel() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        let hasCancel = shortcuts.contains { $0.description.lowercased().contains("cancel") }
        XCTAssertTrue(hasCancel, "Expected a 'cancel' shortcut")
    }

    func test_shortcutsContainRetry() {
        let shortcuts = DataImportKeyboardShortcutsModifier.allShortcuts
        let hasRetry = shortcuts.contains { $0.description.lowercased().contains("retry") || $0.description.lowercased().contains("reload") }
        XCTAssertTrue(hasRetry, "Expected a 'retry' shortcut")
    }

    // MARK: - ViewModel jump (keyboard shortcut side-effect)

    @MainActor
    func test_jumpToStep_mappingCallsLoadPreview() async {
        let repo = MockImportRepository()
        await repo.set(previewResult: .success(.fixture()))
        let vm = ImportWizardViewModel(repository: repo)

        // Advance to .start step so .mapping is in the past
        vm.selectedSource = .csv
        vm.confirmSource()
        vm.confirmEntity()
        // Manually advance jobId (normally set by upload)
        vm.jobId = "job-1"
        // Load preview (advances to .mapping)
        await vm.loadPreview()
        XCTAssertEqual(vm.currentStep, .mapping)

        // Satisfy required fields mapping so confirmMapping() can advance
        let requiredFields = CRMField.requiredFields(for: vm.selectedEntity)
        for field in requiredFields {
            // Map any preview column to this required field
            let col = vm.preview?.columns.first ?? "col"
            vm.columnMapping[col] = field.rawValue
        }
        vm.confirmMapping()
        XCTAssertEqual(vm.currentStep, .start)

        // Now jump back to .mapping
        await repo.set(previewResult: .success(.fixture()))
        vm.jumpToStep(.mapping)

        // Give the async loadPreview() a moment to complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(vm.currentStep, .mapping)
    }

    @MainActor
    func test_jumpToStep_forwardIsNoop() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        // currentStep == .chooseEntity; jumping forward to .mapping is a noop
        vm.jumpToStep(.mapping)
        XCTAssertEqual(vm.currentStep, .chooseEntity)
    }

    @MainActor
    func test_jumpToStep_sameStepIsNoop() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        let before = vm.currentStep
        vm.jumpToStep(.chooseEntity)
        XCTAssertEqual(vm.currentStep, before)
    }

    @MainActor
    func test_jumpToStep_withoutJobIdNoops() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        vm.confirmEntity()
        // No jobId set — jumping to .mapping should be a noop
        vm.jumpToStep(.mapping)
        XCTAssertEqual(vm.currentStep, .upload)
    }
}
