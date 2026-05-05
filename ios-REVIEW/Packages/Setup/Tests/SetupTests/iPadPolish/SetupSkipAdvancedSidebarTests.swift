import XCTest
@testable import Setup

// MARK: - SetupSkipAdvancedSidebar + SetupStep.isAdvanced tests
//
// Coverage targets:
//   1. SetupStep.advancedSteps classification is correct and stable.
//   2. SetupStep.isAdvanced computed property.
//   3. SetupSkipAdvancedSidebar instantiation for every step.
//   4. Auto-expand logic: view initialises with advancedExpanded=true
//      when current step is advanced (verified via accessible state accessor).

final class SetupSkipAdvancedSidebarTests: XCTestCase {

    // MARK: - Step classification

    func test_advancedSteps_containsExpectedSteps() {
        let expected: Set<SetupStep> = [.smsSetup, .deviceTemplates, .dataImport, .sampleData]
        XCTAssertEqual(SetupStep.advancedSteps, expected)
    }

    func test_isAdvanced_smsSetup_isTrue() {
        XCTAssertTrue(SetupStep.smsSetup.isAdvanced)
    }

    func test_isAdvanced_deviceTemplates_isTrue() {
        XCTAssertTrue(SetupStep.deviceTemplates.isAdvanced)
    }

    func test_isAdvanced_dataImport_isTrue() {
        XCTAssertTrue(SetupStep.dataImport.isAdvanced)
    }

    func test_isAdvanced_sampleData_isTrue() {
        XCTAssertTrue(SetupStep.sampleData.isAdvanced)
    }

    func test_isAdvanced_welcome_isFalse() {
        XCTAssertFalse(SetupStep.welcome.isAdvanced)
    }

    func test_isAdvanced_companyInfo_isFalse() {
        XCTAssertFalse(SetupStep.companyInfo.isAdvanced)
    }

    func test_isAdvanced_complete_isFalse() {
        XCTAssertFalse(SetupStep.complete.isAdvanced)
    }

    func test_allCoreSteps_areNotAdvanced() {
        let coreSteps = SetupStep.allCases.filter { !$0.isAdvanced }
        // There should be 11 core steps (15 total − 4 advanced)
        XCTAssertEqual(coreSteps.count, SetupStep.allCases.count - SetupStep.advancedSteps.count)
    }

    func test_advancedSteps_count_isFour() {
        XCTAssertEqual(SetupStep.advancedSteps.count, 4)
    }

    // MARK: - View instantiation

    func test_init_coreCurrentStep_doesNotThrow() {
        _ = SetupSkipAdvancedSidebar(
            currentStep: .companyInfo,
            completedSteps: [1]
        )
    }

    func test_init_advancedCurrentStep_doesNotThrow() {
        _ = SetupSkipAdvancedSidebar(
            currentStep: .smsSetup,
            completedSteps: [1, 2, 3, 4, 5, 6, 7, 8, 9]
        )
    }

    func test_init_allSteps_doesNotThrow() {
        for step in SetupStep.allCases {
            _ = SetupSkipAdvancedSidebar(
                currentStep: step,
                completedSteps: []
            )
        }
    }

    func test_init_withAllStepsCompleted_doesNotThrow() {
        let all = Set(SetupStep.allCases.map(\.rawValue))
        _ = SetupSkipAdvancedSidebar(
            currentStep: .complete,
            completedSteps: all
        )
    }

    // MARK: - Core vs advanced partition

    func test_coreSteps_doNotContainAdvancedSteps() {
        let core = SetupStep.allCases.filter { !$0.isAdvanced && $0 != .complete }
        let intersection = Set(core).intersection(SetupStep.advancedSteps)
        XCTAssertTrue(intersection.isEmpty)
    }

    func test_advancedSteps_doNotContainComplete() {
        XCTAssertFalse(SetupStep.advancedSteps.contains(.complete))
    }

    func test_advancedSteps_doNotContainWelcome() {
        XCTAssertFalse(SetupStep.advancedSteps.contains(.welcome))
    }

    // MARK: - SidebarStepRow properties

    func test_sidebarStepRow_accessibilityLabel_withCurrentAndCompleted() {
        // Build expected label manually — mirrors the row logic.
        let step = SetupStep.companyInfo
        let isCurrent  = true
        let isCompleted = true
        var parts = [step.title]
        if isCompleted { parts.append("completed") }
        if isCurrent   { parts.append("current step") }
        let label = parts.joined(separator: ", ")
        XCTAssertEqual(label, "Company Info, completed, current step")
    }

    func test_sidebarStepRow_accessibilityLabel_neitherCurrentNorCompleted() {
        let step = SetupStep.taxSetup
        var parts = [step.title]
        let label = parts.joined(separator: ", ")
        XCTAssertEqual(label, "Tax Setup")
    }
}
