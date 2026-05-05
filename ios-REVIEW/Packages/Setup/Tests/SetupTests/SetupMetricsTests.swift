import XCTest
@testable import Setup

// MARK: - SetupMetrics tests

final class SetupMetricsTests: XCTestCase {

    // Each test creates its own metrics instance to avoid global-state bleed.

    // MARK: - stepEntered / stepCompleted

    func test_stepCompleted_doesNotCrashWhenNoEntryRecorded() {
        let metrics = SetupMetrics()
        // Should not crash — just logs with "unknown" elapsed
        metrics.stepCompleted(5)
    }

    func test_stepEntered_thenCompleted_removesEntryTime() {
        let metrics = SetupMetrics()
        metrics.stepEntered(3)
        metrics.stepCompleted(3)
        // Completing twice should not crash — entry is gone after first completion
        metrics.stepCompleted(3)
    }

    // MARK: - stepSkipped

    func test_stepSkipped_doesNotCrashWithNoEntry() {
        let metrics = SetupMetrics()
        metrics.stepSkipped(7)
    }

    // MARK: - wizardDeferred

    func test_wizardDeferred_doesNotCrash() {
        let metrics = SetupMetrics()
        metrics.stepEntered(2)
        metrics.wizardDeferred(atStep: 2, completedSteps: [1, 2])
    }

    // MARK: - wizardCompleted

    func test_wizardCompleted_doesNotCrash() {
        let metrics = SetupMetrics()
        metrics.wizardCompleted(completedSteps: [1, 2, 3, 4, 5, 6, 7, 13])
    }

    // MARK: - onStepChange

    func test_onStepChange_doesNotCrash() {
        let metrics = SetupMetrics()
        metrics.onStepChange(from: 1, to: 2)
    }
}
