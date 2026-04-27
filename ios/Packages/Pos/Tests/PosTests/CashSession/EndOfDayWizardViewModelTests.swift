import XCTest
@testable import Pos

/// §39.4 — Unit tests for `EndOfDayWizardViewModel`.
@MainActor
final class EndOfDayWizardViewModelTests: XCTestCase {

    private func makeSUT() -> EndOfDayWizardViewModel { EndOfDayWizardViewModel() }

    // MARK: - Initial state

    func test_initial_wizardState_isIdle() {
        let vm = makeSUT()
        XCTAssertEqual(vm.wizardState, .idle)
    }

    func test_initial_completedSteps_isEmpty() {
        let vm = makeSUT()
        XCTAssertTrue(vm.completedSteps.isEmpty)
    }

    func test_initial_skippedSteps_isEmpty() {
        let vm = makeSUT()
        XCTAssertTrue(vm.skippedSteps.isEmpty)
    }

    func test_initial_canProceed_isFalse() {
        let vm = makeSUT()
        XCTAssertFalse(vm.canProceed)
    }

    func test_initial_currentStep_isFirst() {
        let vm = makeSUT()
        XCTAssertEqual(vm.currentStep, .closeCashShifts)
    }

    // MARK: - markCompleted

    func test_markCompleted_addsToCompletedSet() {
        let vm = makeSUT()
        vm.markCompleted(.closeCashShifts)
        XCTAssertTrue(vm.completedSteps.contains(.closeCashShifts))
    }

    func test_markCompleted_removesFromSkippedSet() {
        let vm = makeSUT()
        // First skip an optional step (simulate skipped then re-done)
        vm.skipStep(.sendCustomerSMS)
        XCTAssertTrue(vm.skippedSteps.contains(.sendCustomerSMS))
        vm.markCompleted(.sendCustomerSMS)
        XCTAssertFalse(vm.skippedSteps.contains(.sendCustomerSMS))
        XCTAssertTrue(vm.completedSteps.contains(.sendCustomerSMS))
    }

    func test_markCompleted_advancesCurrentStep() {
        let vm = makeSUT()
        XCTAssertEqual(vm.currentStep, .closeCashShifts)
        vm.markCompleted(.closeCashShifts)
        XCTAssertEqual(vm.currentStep, .reviewOpenTickets)
    }

    // MARK: - skipStep

    func test_skipStep_optional_addsToSkipped() {
        let vm = makeSUT()
        vm.skipStep(.sendCustomerSMS)
        XCTAssertTrue(vm.skippedSteps.contains(.sendCustomerSMS))
    }

    func test_skipStep_required_doesNothing() {
        let vm = makeSUT()
        vm.skipStep(.closeCashShifts)  // required step
        XCTAssertFalse(vm.skippedSteps.contains(.closeCashShifts))
    }

    func test_skipStep_backupReminder_optional() {
        let vm = makeSUT()
        vm.skipStep(.backupReminder)
        XCTAssertTrue(vm.skippedSteps.contains(.backupReminder))
    }

    // MARK: - canProceed gate

    func test_canProceed_allRequiredDone_returnsTrue() {
        let vm = makeSUT()
        let required = EndOfDayStep.allCases.filter { !$0.isOptional }
        for step in required { vm.markCompleted(step) }
        XCTAssertTrue(vm.canProceed)
    }

    func test_canProceed_missingOneRequired_returnsFalse() {
        let vm = makeSUT()
        let required = EndOfDayStep.allCases.filter { !$0.isOptional }
        for step in required.dropLast() { vm.markCompleted(step) }
        XCTAssertFalse(vm.canProceed)
    }

    func test_canProceed_withSkippedOptional_stillTrue() {
        let vm = makeSUT()
        let required = EndOfDayStep.allCases.filter { !$0.isOptional }
        for step in required { vm.markCompleted(step) }
        vm.skipStep(.sendCustomerSMS)
        vm.skipStep(.backupReminder)
        XCTAssertTrue(vm.canProceed)
    }

    // MARK: - wizardState transitions

    func test_allRequiredComplete_wizardStateBecomesComplete() {
        let vm = makeSUT()
        let required = EndOfDayStep.allCases.filter { !$0.isOptional }
        for step in required { vm.markCompleted(step) }
        XCTAssertEqual(vm.wizardState, .complete)
    }

    func test_abort_setsAbortedState() {
        let vm = makeSUT()
        vm.abort()
        XCTAssertEqual(vm.wizardState, .aborted)
    }

    // MARK: - generateCSV

    func test_generateCSV_populatesData() {
        let vm = makeSUT()
        let row = ReconciliationRow(
            dateTime: Date(),
            invoiceId: 1,
            lineDescription: "Item",
            qty: 1,
            unitPriceCents: 100,
            lineTotalCents: 100,
            tenderMethod: "cash",
            tenderAmountCents: 100
        )
        vm.generateCSV(transactions: [row])
        XCTAssertNotNil(vm.csvData)
        XCTAssertFalse(vm.csvFilename.isEmpty)
    }

    func test_generateCSV_filenameStartsWithReconciliation() {
        let vm = makeSUT()
        vm.generateCSV(transactions: [])
        XCTAssertTrue(vm.csvFilename.hasPrefix("Reconciliation-"))
    }

    // MARK: - EndOfDayStep metadata

    func test_allSteps_haveTitles() {
        for step in EndOfDayStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) has empty title")
        }
    }

    func test_allSteps_haveIcons() {
        for step in EndOfDayStep.allCases {
            XCTAssertFalse(step.icon.isEmpty, "\(step) has empty icon")
        }
    }

    func test_optionalSteps_count() {
        let optional = EndOfDayStep.allCases.filter { $0.isOptional }
        XCTAssertEqual(optional.count, 2)
        XCTAssertTrue(optional.contains(.sendCustomerSMS))
        XCTAssertTrue(optional.contains(.backupReminder))
    }

    func test_stepRawValues_sequential() {
        for (i, step) in EndOfDayStep.allCases.enumerated() {
            XCTAssertEqual(step.rawValue, i, "\(step) rawValue mismatch")
        }
    }
}
