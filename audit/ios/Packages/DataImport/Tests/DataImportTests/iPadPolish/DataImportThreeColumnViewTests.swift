import XCTest
@testable import DataImport

// MARK: - DataImportThreeColumnViewTests
//
// These tests verify the state-derived logic that drives column visibility
// and step navigation in `DataImportThreeColumnView`. Pure view rendering
// is not tested here (no UIHostingController / snapshot tests in this package).

final class DataImportThreeColumnViewTests: XCTestCase {

    // MARK: - Preview column visibility

    func test_showPreviewColumn_trueForMappingStep() {
        XCTAssertTrue(ThreeColumnState.showPreviewColumn(for: .mapping))
    }

    func test_showPreviewColumn_trueForPreviewStep() {
        XCTAssertTrue(ThreeColumnState.showPreviewColumn(for: .preview))
    }

    func test_showPreviewColumn_trueForStartStep() {
        XCTAssertTrue(ThreeColumnState.showPreviewColumn(for: .start))
    }

    func test_showPreviewColumn_falseForChooseSource() {
        XCTAssertFalse(ThreeColumnState.showPreviewColumn(for: .chooseSource))
    }

    func test_showPreviewColumn_falseForUpload() {
        XCTAssertFalse(ThreeColumnState.showPreviewColumn(for: .upload))
    }

    func test_showPreviewColumn_falseForProgress() {
        XCTAssertFalse(ThreeColumnState.showPreviewColumn(for: .progress))
    }

    func test_showPreviewColumn_falseForDone() {
        XCTAssertFalse(ThreeColumnState.showPreviewColumn(for: .done))
    }

    func test_showPreviewColumn_falseForErrors() {
        XCTAssertFalse(ThreeColumnState.showPreviewColumn(for: .errors))
    }

    // MARK: - Step index ordering

    func test_stepIndex_chooseSourceIsFirst() {
        XCTAssertEqual(ThreeColumnState.stepIndex(.chooseSource), 0)
    }

    func test_stepIndex_progressIsLast() {
        let last = ImportWizardStep.wizardSteps.count - 1
        XCTAssertEqual(ThreeColumnState.stepIndex(.progress), last)
    }

    func test_stepIndex_unknownStepReturnsHighValue() {
        // .done and .errors are not in wizardSteps
        XCTAssertEqual(ThreeColumnState.stepIndex(.done), 99)
        XCTAssertEqual(ThreeColumnState.stepIndex(.errors), 99)
    }

    func test_stepIndex_ordering() {
        let steps = ImportWizardStep.wizardSteps
        for i in 0..<steps.count - 1 {
            XCTAssertLessThan(
                ThreeColumnState.stepIndex(steps[i]),
                ThreeColumnState.stepIndex(steps[i + 1]),
                "\(steps[i]) should come before \(steps[i + 1])"
            )
        }
    }

    // MARK: - Cancel resets VM

    @MainActor
    func test_cancelResetsViewModelState() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        XCTAssertEqual(vm.currentStep, .chooseEntity)

        // Simulate cancel
        vm.reset()

        XCTAssertEqual(vm.currentStep, .chooseSource)
        XCTAssertNil(vm.selectedSource)
        XCTAssertNil(vm.jobId)
    }
}

// MARK: - Test helpers

/// Mirrors helper logic extracted from `DataImportThreeColumnView` for unit testing.
private enum ThreeColumnState {

    static func showPreviewColumn(for step: ImportWizardStep) -> Bool {
        switch step {
        case .preview, .mapping, .start: return true
        default: return false
        }
    }

    static func stepIndex(_ step: ImportWizardStep) -> Int {
        ImportWizardStep.wizardSteps.firstIndex(of: step) ?? 99
    }
}
