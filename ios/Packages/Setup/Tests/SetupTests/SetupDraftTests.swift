import XCTest
import Core
@testable import Setup

// MARK: - SetupDraft Encode/Decode

final class SetupDraftCodableTests: XCTestCase {

    func testDraft_roundTrips_withAllFieldsSet() throws {
        let draft = SetupDraft(
            currentStepRaw: 6,
            completedSteps: [1, 2, 3, 4, 5],
            companyName: "Acme Repairs",
            companyAddress: "42 Oak Ave",
            companyPhone: "(555) 123-4567",
            timezone: "America/Chicago",
            currency: "USD",
            locale: "en_US",
            taxName: "GST",
            taxRatePct: 7.5,
            taxApplyTo: "taxable",
            paymentMethods: ["cash", "card"],
            locationName: "HQ",
            locationAddress: "42 Oak Ave",
            locationPhone: "(555) 123-4567",
            firstEmployeeFirstName: "Jane",
            firstEmployeeLastName: "Smith",
            firstEmployeeEmail: "jane@example.com",
            firstEmployeeRole: "technician",
            sampleDataOptIn: true,
            theme: "dark"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(draft)
        let decoded = try decoder.decode(SetupDraft.self, from: data)

        XCTAssertEqual(decoded.currentStepRaw, 6)
        XCTAssertEqual(decoded.completedSteps, [1, 2, 3, 4, 5])
        XCTAssertEqual(decoded.companyName, "Acme Repairs")
        XCTAssertEqual(decoded.timezone, "America/Chicago")
        XCTAssertEqual(decoded.taxRatePct, 7.5)
        XCTAssertEqual(decoded.paymentMethods, ["cash", "card"])
        XCTAssertEqual(decoded.firstEmployeeEmail, "jane@example.com")
        XCTAssertEqual(decoded.sampleDataOptIn, true)
        XCTAssertEqual(decoded.theme, "dark")
    }

    func testDraft_roundTrips_withMinimalFields() throws {
        let draft = SetupDraft()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(draft)
        let decoded = try decoder.decode(SetupDraft.self, from: data)

        XCTAssertEqual(decoded.currentStepRaw, 1)
        XCTAssertTrue(decoded.completedSteps.isEmpty)
        XCTAssertEqual(decoded.companyName, "")
        XCTAssertNil(decoded.timezone)
        XCTAssertNil(decoded.taxName)
        XCTAssertNil(decoded.sampleDataOptIn)
        XCTAssertEqual(decoded.theme, "system")
    }
}

// MARK: - SetupDraftStore

final class SetupDraftStoreTests: XCTestCase {

    private var store: SetupDraftStore!

    override func setUp() async throws {
        try await super.setUp()
        // Isolated suite so tests don't pollute UserDefaults.standard
        let suite = "com.bizarrecrm.test.setup.draft.\(UUID().uuidString)"
        store = SetupDraftStore(store: DraftStore(suiteName: suite))
    }

    override func tearDown() async throws {
        await store.clear()
        store = nil
        try await super.tearDown()
    }

    func testSaveAndLoad_returnsSavedDraft() async throws {
        var draft = SetupDraft()
        draft.companyName = "Repair Co"
        draft.currentStepRaw = 3

        try await store.save(draft)
        let loaded = try await store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.companyName, "Repair Co")
        XCTAssertEqual(loaded?.currentStepRaw, 3)
    }

    func testLoad_whenNoDraft_returnsNil() async throws {
        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testClear_removesStoredDraft() async throws {
        var draft = SetupDraft()
        draft.companyName = "To Be Cleared"
        try await store.save(draft)
        await store.clear()
        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testSave_overwritesPreviousDraft() async throws {
        var draft1 = SetupDraft()
        draft1.companyName = "First"
        try await store.save(draft1)

        var draft2 = SetupDraft()
        draft2.companyName = "Second"
        try await store.save(draft2)

        let loaded = try await store.load()
        XCTAssertEqual(loaded?.companyName, "Second")
    }
}

// MARK: - SetupWizardViewModel Draft Helpers

@MainActor
final class SetupWizardViewModelDraftTests: XCTestCase {

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

    func testMakeDraft_capturesCurrentStep() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 3, completed: [1, 2], totalSteps: 15)
        ))
        await vm.loadServerState()
        let draft = vm.makeDraft()
        XCTAssertEqual(draft.currentStepRaw, 3)
        XCTAssertEqual(Set(draft.completedSteps), [1, 2])
    }

    func testMakeDraft_capturesCompanyInfo() {
        vm.wizardPayload.companyName    = "Test Shop"
        vm.wizardPayload.companyAddress = "1 Main St"
        vm.wizardPayload.companyPhone   = "(555) 000-1234"
        let draft = vm.makeDraft()
        XCTAssertEqual(draft.companyName, "Test Shop")
        XCTAssertEqual(draft.companyAddress, "1 Main St")
        XCTAssertEqual(draft.companyPhone, "(555) 000-1234")
    }

    func testMakeDraft_capturesTaxRate() {
        vm.wizardPayload.taxRate = TaxRate(name: "VAT", ratePct: 20.0, applyTo: .allItems)
        let draft = vm.makeDraft()
        XCTAssertEqual(draft.taxName, "VAT")
        XCTAssertEqual(draft.taxRatePct, 20.0)
        XCTAssertEqual(draft.taxApplyTo, "all")
    }

    func testMakeDraft_capturesFirstEmployee() {
        vm.wizardPayload.firstEmployeeFirstName = "Bob"
        vm.wizardPayload.firstEmployeeLastName  = "Jones"
        vm.wizardPayload.firstEmployeeEmail     = "bob@example.com"
        vm.wizardPayload.firstEmployeeRole      = "technician"
        let draft = vm.makeDraft()
        XCTAssertEqual(draft.firstEmployeeFirstName, "Bob")
        XCTAssertEqual(draft.firstEmployeeEmail, "bob@example.com")
        XCTAssertEqual(draft.firstEmployeeRole, "technician")
    }

    func testMakeDraft_capturesSampleDataOptIn() {
        vm.wizardPayload.sampleDataOptIn = true
        let draft = vm.makeDraft()
        XCTAssertEqual(draft.sampleDataOptIn, true)
    }

    func testApplyDraft_restoresStep() {
        let draft = SetupDraft(currentStepRaw: 5, completedSteps: [1, 2, 3, 4])
        vm.applyDraft(draft)
        XCTAssertEqual(vm.currentStep, .businessHours)
        XCTAssertEqual(vm.completedSteps, [1, 2, 3, 4])
    }

    func testApplyDraft_restoresTaxRate() {
        let draft = SetupDraft(
            taxName: "GST", taxRatePct: 5.0, taxApplyTo: "taxable"
        )
        vm.applyDraft(draft)
        XCTAssertEqual(vm.wizardPayload.taxRate?.name, "GST")
        XCTAssertEqual(vm.wizardPayload.taxRate?.ratePct, 5.0)
        XCTAssertEqual(vm.wizardPayload.taxRate?.applyTo, .taxableOnly)
    }

    func testApplyDraft_nilTaxRate_doesNotSetTaxRate() {
        let draft = SetupDraft() // taxName is nil
        vm.applyDraft(draft)
        XCTAssertNil(vm.wizardPayload.taxRate)
    }

    func testApplyDraft_restoresFirstLocation() {
        let draft = SetupDraft(
            locationName: "HQ",
            locationAddress: "1 Oak St",
            locationPhone: "(555) 123-4567"
        )
        vm.applyDraft(draft)
        XCTAssertEqual(vm.wizardPayload.firstLocation?.name, "HQ")
        XCTAssertEqual(vm.wizardPayload.firstLocation?.address, "1 Oak St")
    }

    func testApplyDraft_unknownStepRaw_keepsWelcome() {
        let draft = SetupDraft(currentStepRaw: 999)
        vm.applyDraft(draft)
        XCTAssertEqual(vm.currentStep, .welcome)
    }

    func testApplyDraft_restoresSampleDataOptIn() {
        let draft = SetupDraft(sampleDataOptIn: false)
        vm.applyDraft(draft)
        XCTAssertEqual(vm.wizardPayload.sampleDataOptIn, false)
    }

    func testApplyDraft_restoresFirstEmployee() {
        let draft = SetupDraft(
            firstEmployeeFirstName: "Alice",
            firstEmployeeLastName: "Wong",
            firstEmployeeEmail: "alice@shop.com",
            firstEmployeeRole: "manager"
        )
        vm.applyDraft(draft)
        XCTAssertEqual(vm.wizardPayload.firstEmployeeFirstName, "Alice")
        XCTAssertEqual(vm.wizardPayload.firstEmployeeEmail, "alice@shop.com")
        XCTAssertEqual(vm.wizardPayload.firstEmployeeRole, "manager")
    }

    func testResumeFromDraft_loadsAndApplies() async throws {
        let suite = "com.bizarrecrm.test.setup.resume.\(UUID().uuidString)"
        let draftStore = SetupDraftStore(store: DraftStore(suiteName: suite))
        var draft = SetupDraft()
        draft.companyName = "Resumed Shop"
        draft.currentStepRaw = 4
        try await draftStore.save(draft)

        await vm.resumeFromDraft(draftStore: draftStore)

        XCTAssertEqual(vm.currentStep, .timezoneLocale)
        XCTAssertEqual(vm.wizardPayload.companyName, "Resumed Shop")

        await draftStore.clear()
    }

    func testResumeFromDraft_noDraft_keepsWelcome() async {
        let suite = "com.bizarrecrm.test.setup.noresume.\(UUID().uuidString)"
        let draftStore = SetupDraftStore(store: DraftStore(suiteName: suite))
        await vm.resumeFromDraft(draftStore: draftStore)
        XCTAssertEqual(vm.currentStep, .welcome)
    }
}

// MARK: - New Step Transitions

@MainActor
final class SetupWizardNewStepTests: XCTestCase {

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

    func testFirstEmployeeStep_inStepEnum() {
        XCTAssertEqual(SetupStep.firstEmployee.rawValue, 9)
        XCTAssertEqual(SetupStep.firstEmployee.title, "First Employee")
    }

    func testSampleDataStep_inStepEnum() {
        XCTAssertEqual(SetupStep.sampleData.rawValue, 14)
        XCTAssertEqual(SetupStep.sampleData.title, "Sample Data")
    }

    func testCompleteStep_isNow15() {
        XCTAssertEqual(SetupStep.complete.rawValue, 15)
    }

    func testGoNext_fromFirstEmployee_advancesToSmsSetup() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 9, completed: Array(1..<9), totalSteps: 15)
        ))
        await vm.loadServerState()
        XCTAssertEqual(vm.currentStep, .firstEmployee)
        await vm.goNext()
        XCTAssertEqual(vm.currentStep, .smsSetup)
    }

    func testGoNext_fromSampleData_advancesToComplete() async {
        await repo.setFetchStatus(.success(
            SetupStatusResponse(currentStep: 14, completed: Array(1..<14), totalSteps: 15)
        ))
        await vm.loadServerState()
        XCTAssertEqual(vm.currentStep, .sampleData)
        await vm.goNext()
        XCTAssertEqual(vm.currentStep, .complete)
    }

    func testFirstEmployeePayload_serialisesCorrectly() {
        vm.wizardPayload.firstEmployeeFirstName = "Jane"
        vm.wizardPayload.firstEmployeeLastName  = "Doe"
        vm.wizardPayload.firstEmployeeEmail     = "jane@shop.com"
        vm.wizardPayload.firstEmployeeRole      = "manager"
        let p = vm.wizardPayload.firstEmployeePayload()
        XCTAssertEqual(p["first_name"], "Jane")
        XCTAssertEqual(p["last_name"],  "Doe")
        XCTAssertEqual(p["email"],      "jane@shop.com")
        XCTAssertEqual(p["role"],       "manager")
    }

    func testFirstEmployeePayload_emptyWhenNilFields() {
        let p = vm.wizardPayload.firstEmployeePayload()
        XCTAssertTrue(p.isEmpty)
    }

    func testSampleDataPayload_trueOptIn() {
        vm.wizardPayload.sampleDataOptIn = true
        let p = vm.wizardPayload.sampleDataPayload()
        XCTAssertEqual(p["sample_data_opt_in"], "1")
    }

    func testSampleDataPayload_falseOptIn() {
        vm.wizardPayload.sampleDataOptIn = false
        let p = vm.wizardPayload.sampleDataPayload()
        XCTAssertEqual(p["sample_data_opt_in"], "0")
    }

    func testSampleDataPayload_nilOptIn_isEmpty() {
        let p = vm.wizardPayload.sampleDataPayload()
        XCTAssertTrue(p.isEmpty)
    }

    func testTotalStepCount_is15() {
        XCTAssertEqual(SetupStep.totalCount, 15)
    }
}

// MARK: - FirstEmployeeViewModel

@MainActor
final class FirstEmployeeViewModelTests: XCTestCase {

    func testInitialState_isNextEnabled_noInput() {
        let vm = FirstEmployeeViewModel()
        XCTAssertTrue(vm.isNextEnabled, "No input = skippable = valid")
    }

    func testWithValidInput_isNextEnabled() {
        let vm = FirstEmployeeViewModel()
        vm.firstName = "Jane"
        vm.lastName  = "Doe"
        vm.email     = "jane@example.com"
        XCTAssertTrue(vm.isNextEnabled)
    }

    func testWithPartialInput_invalidEmail_isNotNextEnabled() {
        let vm = FirstEmployeeViewModel()
        vm.firstName = "Jane"
        vm.lastName  = "Doe"
        vm.email     = "not-an-email"
        XCTAssertFalse(vm.isNextEnabled)
    }

    func testWithPartialInput_missingLastName_isNotNextEnabled() {
        let vm = FirstEmployeeViewModel()
        vm.firstName = "Jane"
        vm.email     = "jane@example.com"
        // lastName is empty — partial input with missing required field
        XCTAssertFalse(vm.isNextEnabled)
    }

    func testAsPayload_allFilled_returnsPayload() {
        let vm = FirstEmployeeViewModel()
        vm.firstName = "Jane"
        vm.lastName  = "Doe"
        vm.email     = "jane@example.com"
        vm.role      = .manager
        let p = vm.asPayload
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.firstName, "Jane")
        XCTAssertEqual(p?.role, .manager)
    }

    func testAsPayload_blank_returnsNil() {
        let vm = FirstEmployeeViewModel()
        XCTAssertNil(vm.asPayload)
    }

    func testOnFirstNameBlur_setsError_whenTooLong() {
        let vm = FirstEmployeeViewModel()
        vm.firstName = String(repeating: "a", count: 101)
        vm.onFirstNameBlur()
        XCTAssertNotNil(vm.firstNameError)
    }

    func testOnEmailBlur_setsError_forInvalidEmail() {
        let vm = FirstEmployeeViewModel()
        vm.email = "not-valid"
        vm.onEmailBlur()
        XCTAssertNotNil(vm.emailError)
    }

    func testOnEmailBlur_clearsError_forValidEmail() {
        let vm = FirstEmployeeViewModel()
        vm.email = "valid@example.com"
        vm.onEmailBlur()
        XCTAssertNil(vm.emailError)
    }

    func testHasAnyInput_false_whenAllEmpty() {
        let vm = FirstEmployeeViewModel()
        XCTAssertFalse(vm.hasAnyInput)
    }

    func testHasAnyInput_true_whenOnlyEmailEntered() {
        let vm = FirstEmployeeViewModel()
        vm.email = "x@y.com"
        XCTAssertTrue(vm.hasAnyInput)
    }
}

// MARK: - SampleDataOptInViewModel

@MainActor
final class SampleDataOptInViewModelTests: XCTestCase {

    func testInitialState_isNextEnabled_isFalse() {
        let vm = SampleDataOptInViewModel()
        XCTAssertFalse(vm.isNextEnabled, "No choice selected yet")
    }

    func testChoiceYes_isNextEnabled() {
        let vm = SampleDataOptInViewModel()
        vm.choice = .yes
        XCTAssertTrue(vm.isNextEnabled)
    }

    func testChoiceNo_isNextEnabled() {
        let vm = SampleDataOptInViewModel()
        vm.choice = .no
        XCTAssertTrue(vm.isNextEnabled)
    }

    func testChoiceYes_isDistinctFromNo() {
        let vm = SampleDataOptInViewModel()
        vm.choice = .yes
        XCTAssertNotEqual(vm.choice, .no)
    }

    func testInitialLoadError_isNil() {
        let vm = SampleDataOptInViewModel()
        XCTAssertNil(vm.loadError)
    }
}
