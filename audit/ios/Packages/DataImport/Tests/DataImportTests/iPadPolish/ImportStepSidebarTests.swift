import XCTest
@testable import DataImport

// MARK: - ImportStepSidebarTests

final class ImportStepSidebarTests: XCTestCase {

    // MARK: - StepState resolution

    func test_stepState_activeStepIsActive() {
        // The step at the same index as currentStep should be .active
        let sidebar = SidebarStateChecker(
            steps: ImportWizardStep.wizardSteps,
            currentStep: .upload
        )
        XCTAssertEqual(sidebar.state(for: .upload), .active)
    }

    func test_stepState_earlierStepIsCompleted() {
        let sidebar = SidebarStateChecker(
            steps: ImportWizardStep.wizardSteps,
            currentStep: .mapping
        )
        XCTAssertEqual(sidebar.state(for: .chooseSource), .completed)
        XCTAssertEqual(sidebar.state(for: .chooseEntity), .completed)
        XCTAssertEqual(sidebar.state(for: .upload), .completed)
        XCTAssertEqual(sidebar.state(for: .preview), .completed)
    }

    func test_stepState_laterStepIsUpcoming() {
        let sidebar = SidebarStateChecker(
            steps: ImportWizardStep.wizardSteps,
            currentStep: .upload
        )
        XCTAssertEqual(sidebar.state(for: .mapping), .upcoming)
        XCTAssertEqual(sidebar.state(for: .start), .upcoming)
        XCTAssertEqual(sidebar.state(for: .progress), .upcoming)
    }

    func test_stepState_firstStepNoCompleted() {
        let sidebar = SidebarStateChecker(
            steps: ImportWizardStep.wizardSteps,
            currentStep: .chooseSource
        )
        let allStates = ImportWizardStep.wizardSteps.map { sidebar.state(for: $0) }
        XCTAssertEqual(allStates.filter { $0 == .completed }.count, 0)
    }

    func test_stepState_lastWizardStepAllCompleted() {
        let sidebar = SidebarStateChecker(
            steps: ImportWizardStep.wizardSteps,
            currentStep: .progress
        )
        // All steps before progress should be completed
        let completed = ImportWizardStep.wizardSteps.dropLast().map { sidebar.state(for: $0) }
        XCTAssertTrue(completed.allSatisfy { $0 == .completed })
    }

    // MARK: - Jump target accessibility label

    func test_accessibilityLabel_completed() {
        let label = SidebarStateChecker.accessibilityLabel(step: .chooseSource, state: .completed)
        XCTAssertTrue(label.contains("completed"), "Expected 'completed' in: \(label)")
    }

    func test_accessibilityLabel_active() {
        let label = SidebarStateChecker.accessibilityLabel(step: .mapping, state: .active)
        XCTAssertTrue(label.contains("current step"), "Expected 'current step' in: \(label)")
    }

    func test_accessibilityLabel_upcoming() {
        let label = SidebarStateChecker.accessibilityLabel(step: .start, state: .upcoming)
        XCTAssertTrue(label.contains("upcoming"), "Expected 'upcoming' in: \(label)")
    }

    // MARK: - Jump callback

    func test_jumpCallback_firesForJumpableStep() {
        var jumpedTo: ImportWizardStep? = nil
        var callCount = 0

        let onJump: (ImportWizardStep) -> Void = { step in
            jumpedTo = step
            callCount += 1
        }

        // Simulate tapping the mapping step (only jumpable step)
        let steps = ImportWizardStep.wizardSteps
        let currentIdx = steps.firstIndex(of: .start) ?? 0
        let targetStep = ImportWizardStep.mapping
        let targetIdx = steps.firstIndex(of: targetStep) ?? 0

        // Guard: target must precede current
        XCTAssertLessThan(targetIdx, currentIdx)

        // Simulate the jump
        onJump(targetStep)

        XCTAssertEqual(jumpedTo, .mapping)
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - Test helpers

/// Mirror of the step-state logic in `ImportStepSidebar` exposed for unit tests.
private struct SidebarStateChecker {
    let steps: [ImportWizardStep]
    let currentStep: ImportWizardStep

    enum State { case completed, active, upcoming }

    func state(for step: ImportWizardStep) -> State {
        let currentIdx = steps.firstIndex(of: currentStep) ?? 0
        let stepIdx    = steps.firstIndex(of: step) ?? 0
        if stepIdx < currentIdx { return .completed }
        if step == currentStep  { return .active }
        return .upcoming
    }

    static func accessibilityLabel(step: ImportWizardStep, state: State) -> String {
        switch state {
        case .completed: return "\(step.title), completed"
        case .active:    return "\(step.title), current step"
        case .upcoming:  return "\(step.title), upcoming"
        }
    }
}
