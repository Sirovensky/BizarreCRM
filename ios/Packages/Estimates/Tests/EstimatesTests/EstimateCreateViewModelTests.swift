import XCTest
@testable import Estimates
import Networking
import Core

// §63 ext — EstimateCreateViewModel draft recovery + AppError mapping tests

@MainActor
final class EstimateCreateViewModelTests: XCTestCase {

    private func makeSut(
        createResult: Result<CreatedResource, Error> = .success(.init(id: 1))
    ) -> EstimateCreateViewModel {
        EstimateCreateViewModel(api: StubAPIClient(createResult: createResult))
    }

    // MARK: — Validation

    func test_isValid_falseWithoutCustomer() {
        XCTAssertFalse(makeSut().isValid)
    }

    func test_isValid_trueWithCustomer() {
        let vm = makeSut()
        vm.customerId = 1
        XCTAssertTrue(vm.isValid)
    }

    // MARK: — submit without customer

    func test_submit_withoutCustomer_setsError() async {
        let vm = makeSut()
        await vm.submit()
        XCTAssertEqual(vm.errorMessage, "Pick a customer first.")
        XCTAssertNil(vm.createdId)
    }

    // MARK: — happy path

    func test_submit_happyPath_populatesCreatedId() async {
        let vm = makeSut(createResult: .success(.init(id: 33)))
        vm.customerId = 2
        await vm.submit()
        XCTAssertEqual(vm.createdId, 33)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: — restoreDraft fills all fields

    func test_restoreDraft_populatesFields() {
        let vm = makeSut()
        let draft = EstimateDraft(
            customerId: "5",
            customerDisplayName: "Beta Co",
            subject: "Battery replacement",
            notes: "Urgent",
            validUntil: "2025-11-30"
        )
        vm._pendingDraft = draft
        vm._draftRecord  = DraftRecord(screen: "estimate.create", entityId: nil, updatedAt: Date(), bytes: 10)

        vm.restoreDraft()

        XCTAssertEqual(vm.customerId, 5)
        XCTAssertEqual(vm.customerDisplayName, "Beta Co")
        XCTAssertEqual(vm.subject, "Battery replacement")
        XCTAssertEqual(vm.notes, "Urgent")
        XCTAssertEqual(vm.validUntil, "2025-11-30")
        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — discardDraft clears state

    func test_discardDraft_clearsPendingAndRecord() {
        let vm = makeSut()
        vm._pendingDraft = EstimateDraft(customerId: "1")
        vm._draftRecord  = DraftRecord(screen: "estimate.create", entityId: nil, updatedAt: Date(), bytes: 5)

        vm.discardDraft()

        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — currentDraft captures fields

    func test_currentDraft_capturesFields() {
        let vm = makeSut()
        vm.customerId = 99
        vm.subject = "Repair quote"
        vm.notes = "Customer needs it fast"
        vm.validUntil = "2025-09-01"

        let draft = vm.currentDraft()

        XCTAssertEqual(draft.customerId, "99")
        XCTAssertEqual(draft.subject, "Repair quote")
        XCTAssertEqual(draft.notes, "Customer needs it fast")
        XCTAssertEqual(draft.validUntil, "2025-09-01")
    }

    // MARK: — AppError: offline

    func test_handleAppError_offline_queuedOfflineAndMessage() async {
        let vm = makeSut()
        vm.customerId = 1

        await vm.handleAppError(.offline)

        XCTAssertTrue(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "You're offline. Your draft will sync when you reconnect.")
    }

    // MARK: — AppError: validation

    func test_handleAppError_validation_setsFieldErrors() async {
        let vm = makeSut()

        await vm.handleAppError(.validation(fieldErrors: ["subject": "Subject is required"]))

        XCTAssertFalse(vm.validationErrors.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: — AppError: conflict

    func test_handleAppError_conflict_showsRefreshHint() async {
        let vm = makeSut()

        await vm.handleAppError(.conflict(reason: nil))

        XCTAssertEqual(vm.errorMessage, "Estimate already exists. Pull to refresh?")
    }

    // MARK: — AppError: rate limited includes suggestion

    func test_handleAppError_rateLimited_includesWaitSuggestion() async {
        let vm = makeSut()

        await vm.handleAppError(.rateLimited(retryAfterSeconds: 30))

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("30") == true || vm.errorMessage?.contains("wait") == true || vm.errorMessage?.contains("Wait") == true)
    }

    // MARK: — DraftRecoverable screenId

    func test_screenId_isStable() {
        XCTAssertEqual(EstimateCreateViewModel.screenId, "estimate.create")
    }

    // MARK: — scheduleAutoSave does not crash

    func test_scheduleAutoSave_doesNotCrash() {
        let vm = makeSut()
        vm.customerId = 1
        vm.scheduleAutoSave()
    }
}
