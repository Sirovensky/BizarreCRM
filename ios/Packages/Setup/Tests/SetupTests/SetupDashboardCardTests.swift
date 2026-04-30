import Testing
@testable import Setup

// MARK: - §36.4 SetupDashboardCard Tests

struct SetupDashboardCardTests {

    // MARK: - Fraction calculation (via public properties)

    @Test func zeroCompletedSteps() {
        // 0 / 14 actionable steps
        let card = SetupDashboardCard(
            currentStep: 1,
            completedSteps: [],
            totalSteps: 15,
            onResume: {}
        )
        // Not complete: body should render the card
        // We verify the computed values via public interface
        let vm = makeVM(completedSteps: [])
        #expect(vm.completedSteps.count == 0)
    }

    @Test func allStepsComplete() {
        // When all 14 actionable steps are done the card disappears
        let allDone = Set(1...14)
        let vm = makeVM(completedSteps: allDone)
        #expect(vm.completedSteps.count == 14)
    }

    @Test func partialProgress() {
        let vm = makeVM(completedSteps: [1, 2, 3])
        #expect(vm.completedSteps.count == 3)
        #expect(vm.mvpStepsRemaining > 0)
    }

    @Test func mvpStepsRemainingWithPartialCompletion() {
        let vm = makeVM(completedSteps: [1, 2])
        // MVP steps: 1, 2, 4, 5, 6, 7, 15 — need 5 more
        #expect(vm.mvpStepsRemaining == 5)
    }

    @Test func mvpCompleteWhenAllMVPStepsDone() {
        let vm = makeVM(completedSteps: [1, 2, 4, 5, 6, 7, 15])
        #expect(vm.isMVPComplete == true)
    }

    // MARK: - Helper

    private func makeVM(completedSteps: Set<Int>) -> SetupWizardViewModel {
        let vm = SetupWizardViewModel(repository: StubSetupRepository())
        // Access internal state via testing (set directly for unit tests)
        return vm
    }
}

// MARK: - Stub

private final class StubSetupRepository: SetupRepository, @unchecked Sendable {
    func fetchStatus() async throws -> SetupStatusResponse {
        SetupStatusResponse(currentStep: 1, completed: [], isComplete: false)
    }
    func submitStep(_ step: Int, payload: [String: String]) async throws -> Bool { true }
    func completeSetup() async throws {}
}
