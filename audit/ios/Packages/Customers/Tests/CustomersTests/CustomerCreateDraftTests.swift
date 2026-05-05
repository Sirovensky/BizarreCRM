import XCTest
@testable import Customers
import Networking
import Core

// §63 ext — CustomerCreateViewModel draft recovery + AppError mapping tests

@MainActor
final class CustomerCreateDraftTests: XCTestCase {

    private func makeSut(
        createResult: Result<CreatedResource, Error> = .success(.init(id: 1))
    ) -> CustomerCreateViewModel {
        CustomerCreateViewModel(api: StubAPIClient(createResult: createResult))
    }

    // MARK: — restoreDraft fills all fields

    func test_restoreDraft_populatesAllFields() {
        let vm = makeSut()
        let draft = CustomerDraft(
            firstName: "Ada", lastName: "Lovelace",
            email: "ada@example.com", phone: "555-1234",
            mobile: "555-5678", organization: "Acme",
            address1: "123 Main St", city: "Springfield",
            state: "IL", postcode: "62701",
            notes: "VIP customer"
        )
        vm._pendingDraft = draft
        vm._draftRecord  = DraftRecord(screen: "customer.create", entityId: nil, updatedAt: Date(), bytes: 10)

        vm.restoreDraft()

        XCTAssertEqual(vm.firstName, "Ada")
        XCTAssertEqual(vm.lastName, "Lovelace")
        XCTAssertEqual(vm.email, "ada@example.com")
        XCTAssertEqual(vm.phone, "555-1234")
        XCTAssertEqual(vm.organization, "Acme")
        XCTAssertEqual(vm.notes, "VIP customer")
        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — discardDraft clears both pending and record

    func test_discardDraft_clearsPendingAndRecord() {
        let vm = makeSut()
        vm._pendingDraft = CustomerDraft(firstName: "Temp")
        vm._draftRecord  = DraftRecord(screen: "customer.create", entityId: nil, updatedAt: Date(), bytes: 5)

        vm.discardDraft()

        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — currentDraft captures all form fields

    func test_currentDraft_capturesAllFields() {
        let vm = makeSut()
        vm.firstName    = "Bob"
        vm.lastName     = "Smith"
        vm.email        = "bob@test.com"
        vm.organization = "BigCo"

        let draft = vm.currentDraft()

        XCTAssertEqual(draft.firstName, "Bob")
        XCTAssertEqual(draft.lastName, "Smith")
        XCTAssertEqual(draft.email, "bob@test.com")
        XCTAssertEqual(draft.organization, "BigCo")
    }

    // MARK: — handleAppError: offline

    func test_handleAppError_offline_setsDraftSyncMessage() async {
        let vm = makeSut()
        vm.firstName = "Test"

        await vm.handleAppError(.offline)

        XCTAssertEqual(vm.errorMessage, "You're offline. Your draft will sync when you reconnect.")
    }

    // MARK: — handleAppError: validation

    func test_handleAppError_validation_setsFieldErrors() async {
        let vm = makeSut()

        await vm.handleAppError(.validation(fieldErrors: ["email": "Invalid email address"]))

        XCTAssertFalse(vm.validationErrors.isEmpty)
        XCTAssertEqual(vm.validationErrors["email"], "Invalid email address")
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: — handleAppError: conflict

    func test_handleAppError_conflict_showsRefreshHint() async {
        let vm = makeSut()

        await vm.handleAppError(.conflict(reason: nil))

        XCTAssertEqual(vm.errorMessage, "Customer already exists. Pull to refresh?")
    }

    // MARK: — handleAppError: unauthorized includes suggestion

    func test_handleAppError_unauthorized_includesSuggestion() async {
        let vm = makeSut()

        await vm.handleAppError(.unauthorized)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("sign") == true || vm.errorMessage?.contains("session") == true)
    }

    // MARK: — scheduleAutoSave does not crash

    func test_scheduleAutoSave_doesNotCrash() {
        let vm = makeSut()
        vm.firstName = "Quick"
        vm.scheduleAutoSave()
    }

    // MARK: — submit success clears draft

    func test_submit_success_clears_draft_logically() async {
        let vm = makeSut(createResult: .success(.init(id: 7)))
        vm.firstName = "Jane"

        await vm.submit()

        XCTAssertEqual(vm.createdId, 7)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: — DraftRecoverable conformance

    func test_screenId_isStable() {
        XCTAssertEqual(CustomerCreateViewModel.screenId, "customer.create")
    }
}
