import XCTest
@testable import Setup

// MARK: - Mock repository

actor MockSetupRepository: SetupRepository {
    private var fetchStatusResult: Result<SetupStatusResponse, Error> = .success(
        SetupStatusResponse(currentStep: 1, completed: [], totalSteps: 13)
    )
    private var submitStepResult: Result<Int, Error> = .success(2)
    private var uploadLogoResult: Result<String, Error> = .success("https://cdn.example.com/logo.png")
    private var completeSetupResult: Result<Void, Error> = .success(())

    private(set) var submitStepCalls: [(step: Int, payload: [String: String])] = []
    private(set) var completeSetupCallCount: Int = 0

    // MARK: Mutation helpers (actor-isolated)

    func setFetchStatus(_ result: Result<SetupStatusResponse, Error>) {
        fetchStatusResult = result
    }

    func setSubmitStep(_ result: Result<Int, Error>) {
        submitStepResult = result
    }

    func setCompleteSetup(_ result: Result<Void, Error>) {
        completeSetupResult = result
    }

    // MARK: Protocol conformance

    func fetchStatus() async throws -> SetupStatusResponse {
        try fetchStatusResult.get()
    }

    func submitStep(_ step: Int, payload: [String: String]) async throws -> Int {
        submitStepCalls.append((step: step, payload: payload))
        return try submitStepResult.get()
    }

    func uploadLogo(data: Data) async throws -> String {
        try uploadLogoResult.get()
    }

    func completeSetup() async throws {
        completeSetupCallCount += 1
        try completeSetupResult.get()
    }
}

// MARK: - Tests

@MainActor
final class SetupWizardViewModelTests: XCTestCase {

    private var repo: MockSetupRepository!
    private var vm: SetupWizardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        repo = MockSetupRepository()
        vm = SetupWizardViewModel(repository: repo)
    }

    override func tearDown() async throws {
        vm = nil
        repo = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testInitialStep_isWelcome() {
        XCTAssertEqual(vm.currentStep, .welcome)
    }

    func testInitialCompletedSteps_isEmpty() {
        XCTAssertTrue(vm.completedSteps.isEmpty)
    }

    func testInitialIsSaving_isFalse() {
        XCTAssertFalse(vm.isSaving)
    }

    func testInitialIsPresented_isTrue() {
        XCTAssertTrue(vm.isPresented)
    }

    func testInitialIsDismissed_isFalse() {
        XCTAssertFalse(vm.isDismissed)
    }

    // MARK: - Step progression

    func testGoNext_advancesStep() async {
        await vm.goNext()
        XCTAssertEqual(vm.currentStep, .companyInfo)
    }

    func testGoNext_marksStepCompleted() async {
        await vm.goNext()
        XCTAssertTrue(vm.completedSteps.contains(1))
    }

    func testGoNext_submitsPayload() async {
        vm.pendingPayload = ["name": "Bizarre Shop"]
        await vm.goNext()
        let calls = await repo.submitStepCalls
        XCTAssertEqual(calls.first?.step, 1)
        XCTAssertEqual(calls.first?.payload["name"], "Bizarre Shop")
    }

    func testGoNext_twice_reachesLogoStep() async {
        await vm.goNext()
        await vm.goNext()
        XCTAssertEqual(vm.currentStep, .logo)
    }

    // MARK: - Back navigation

    func testGoBack_fromStep2_returnsToStep1() async {
        await vm.goNext()
        vm.goBack()
        XCTAssertEqual(vm.currentStep, .welcome)
    }

    func testCanGoBack_onStep1_isFalse() {
        XCTAssertFalse(vm.canGoBack)
    }

    func testCanGoBack_onStep2_isTrue() async {
        await vm.goNext()
        XCTAssertTrue(vm.canGoBack)
    }

    // MARK: - Skip

    func testSkipStep_advancesWithoutSubmitting() async {
        await vm.skipStep()
        XCTAssertEqual(vm.currentStep, .companyInfo)
        let calls = await repo.submitStepCalls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Defer / Do Later

    func testDeferWizard_setsDismissed() {
        vm.deferWizard()
        XCTAssertTrue(vm.isDismissed)
        XCTAssertFalse(vm.isPresented)
    }

    func testDeferWizard_postsNotification() {
        let expectation = expectation(forNotification: .setupStatusDeferred, object: nil)
        vm.deferWizard()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Progress

    func testProgress_step1_isZero() {
        XCTAssertEqual(vm.progress, 0.0, accuracy: 0.001)
    }

    func testProgress_lastStep_isOne() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 13, completed: Array(1...12), totalSteps: 13)
        ))
        await vm.loadServerState()
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    // MARK: - Server state loading

    func testLoadServerState_setsCurrentStep() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 3, completed: [1, 2], totalSteps: 13)
        ))
        await vm.loadServerState()
        XCTAssertEqual(vm.currentStep, .logo)
        XCTAssertEqual(vm.completedSteps, [1, 2])
    }

    func testLoadServerState_networkFailure_keepDefault() async {
        await repo.setFetchStatus(.failure(URLError(.notConnectedToInternet)))
        await vm.loadServerState()
        XCTAssertEqual(vm.currentStep, .welcome)
    }

    // MARK: - Submit error handling

    func testGoNext_submitFailure_showsError() async {
        await repo.setSubmitStep(.failure(URLError(.badServerResponse)))
        await vm.goNext()
        XCTAssertNotNil(vm.errorMessage)
    }

    func testGoNext_submitFailure_doesNotMarkCompleted() async {
        await repo.setSubmitStep(.failure(URLError(.badServerResponse)))
        await vm.goNext()
        XCTAssertFalse(vm.completedSteps.contains(1))
    }

    // MARK: - Completion

    func testFinishWizard_callsComplete() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 13, completed: Array(1...12), totalSteps: 13)
        ))
        await vm.loadServerState()
        await vm.goNext()
        let count = await repo.completeSetupCallCount
        XCTAssertEqual(count, 1)
    }

    func testFinishWizard_success_dismisses() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 13, completed: Array(1...12), totalSteps: 13)
        ))
        await vm.loadServerState()
        await vm.goNext()
        XCTAssertTrue(vm.isDismissed)
        XCTAssertFalse(vm.isPresented)
    }

    func testFinishWizard_failure_showsError() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 13, completed: Array(1...12), totalSteps: 13)
        ))
        await vm.loadServerState()
        await repo.setCompleteSetup(.failure(URLError(.badServerResponse)))
        await vm.goNext()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isDismissed)
    }

    // MARK: - Persistence / state immutability

    func testCompletedSteps_isImmutableSnapshot() async {
        await vm.goNext()
        let snapshot = vm.completedSteps
        await vm.goNext()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertGreaterThanOrEqual(vm.completedSteps.count, 2)
    }

    func testPendingPayload_clearedAfterSubmit() async {
        vm.pendingPayload = ["key": "value"]
        await vm.goNext()
        XCTAssertTrue(vm.pendingPayload.isEmpty)
    }
}
