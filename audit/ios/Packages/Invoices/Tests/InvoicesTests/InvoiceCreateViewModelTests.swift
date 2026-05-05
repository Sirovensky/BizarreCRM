import XCTest
@testable import Invoices
import Networking
import Core

// §63 ext — InvoiceCreateViewModel draft recovery + AppError mapping tests

@MainActor
final class InvoiceCreateViewModelTests: XCTestCase {

    private func makeSut(
        createResult: Result<CreatedResource, Error> = .success(.init(id: 1))
    ) -> InvoiceCreateViewModel {
        InvoiceCreateViewModel(api: StubAPIClient(createResult: createResult))
    }

    // MARK: — isValid requires customerId

    func test_isValid_falseWithoutCustomer() {
        let vm = makeSut()
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWithCustomer() {
        let vm = makeSut()
        vm.customerId = 1
        XCTAssertTrue(vm.isValid)
    }

    // MARK: — submit without customer sets error

    func test_submit_withoutCustomer_setsError() async {
        let vm = makeSut()
        await vm.submit()
        XCTAssertEqual(vm.errorMessage, "Pick a customer first.")
        XCTAssertNil(vm.createdId)
    }

    // MARK: — submit happy path

    func test_submit_happyPath_populatesCreatedId() async {
        let vm = makeSut(createResult: .success(.init(id: 55)))
        vm.customerId = 1
        await vm.submit()
        XCTAssertEqual(vm.createdId, 55)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: — restoreDraft fills fields

    func test_restoreDraft_populatesFields() {
        let vm = makeSut()
        let draft = InvoiceDraft(customerId: "7", customerDisplayName: "Acme Corp",
                                 notes: "Rush order", dueOn: "2025-12-31")
        vm._pendingDraft = draft
        vm._draftRecord  = DraftRecord(screen: "invoice.create", entityId: nil, updatedAt: Date(), bytes: 10)

        vm.restoreDraft()

        XCTAssertEqual(vm.customerId, 7)
        XCTAssertEqual(vm.customerDisplayName, "Acme Corp")
        XCTAssertEqual(vm.notes, "Rush order")
        XCTAssertEqual(vm.dueOn, "2025-12-31")
        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — discardDraft clears state

    func test_discardDraft_clearsPendingAndRecord() {
        let vm = makeSut()
        vm._pendingDraft = InvoiceDraft(customerId: "1")
        vm._draftRecord  = DraftRecord(screen: "invoice.create", entityId: nil, updatedAt: Date(), bytes: 5)

        vm.discardDraft()

        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: — currentDraft captures fields

    func test_currentDraft_capturesFields() {
        let vm = makeSut()
        vm.customerId = 42
        vm.notes = "Test notes"
        vm.dueOn = "2025-06-30"

        let draft = vm.currentDraft()

        XCTAssertEqual(draft.customerId, "42")
        XCTAssertEqual(draft.notes, "Test notes")
        XCTAssertEqual(draft.dueOn, "2025-06-30")
    }

    // MARK: — handleAppError: offline

    func test_handleAppError_offline_savesDraftAndSetsMessage() async {
        let vm = makeSut()
        vm.customerId = 1
        vm.notes = "Important"

        await vm.handleAppError(.offline)

        XCTAssertTrue(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "You're offline. Your draft will sync when you reconnect.")
    }

    // MARK: — handleAppError: validation

    func test_handleAppError_validation_setsFieldErrors() async {
        let vm = makeSut()

        await vm.handleAppError(.validation(fieldErrors: ["notes": "Notes too long"]))

        XCTAssertFalse(vm.validationErrors.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: — handleAppError: conflict

    func test_handleAppError_conflict_showsRefreshHint() async {
        let vm = makeSut()

        await vm.handleAppError(.conflict(reason: nil))

        XCTAssertEqual(vm.errorMessage, "Invoice already exists. Pull to refresh?")
    }

    // MARK: — DraftRecoverable screenId

    func test_screenId_isStable() {
        XCTAssertEqual(InvoiceCreateViewModel.screenId, "invoice.create")
    }

    // MARK: — scheduleAutoSave does not crash

    func test_scheduleAutoSave_doesNotCrash() {
        let vm = makeSut()
        vm.customerId = 1
        vm.scheduleAutoSave()
    }

    // MARK: — §7.3 Line item management

    func test_addLineItem_appendsToList() {
        let vm = makeSut()
        XCTAssertTrue(vm.lineItems.isEmpty)
        vm.addLineItem()
        XCTAssertEqual(vm.lineItems.count, 1)
    }

    func test_addLineItem_multipleItems_allAppended() {
        let vm = makeSut()
        vm.addLineItem()
        vm.addLineItem()
        vm.addLineItem()
        XCTAssertEqual(vm.lineItems.count, 3)
    }

    func test_removeLineItem_byId_removesCorrectItem() {
        let vm = makeSut()
        vm.addLineItem()
        vm.addLineItem()
        let idToRemove = vm.lineItems[0].id
        vm.removeLineItem(id: idToRemove)
        XCTAssertEqual(vm.lineItems.count, 1)
        XCTAssertFalse(vm.lineItems.contains { $0.id == idToRemove })
    }

    func test_lineItemsSubtotal_correctlyComputed() {
        let vm = makeSut()
        vm.addLineItem()
        vm.lineItems[0].unitPrice = 100
        vm.lineItems[0].quantity = 2
        vm.lineItems[0].taxAmount = 10
        vm.lineItems[0].lineDiscount = 5
        // lineTotal = 100 * 2 - 5 + 10 = 205
        XCTAssertEqual(vm.lineItemsSubtotal, 205, accuracy: 0.01)
    }

    func test_computedTotal_subtractCartDiscount() {
        let vm = makeSut()
        vm.addLineItem()
        vm.lineItems[0].unitPrice = 100
        vm.lineItems[0].quantity = 1
        vm.cartDiscount = 20
        // 100 - 20 = 80
        XCTAssertEqual(vm.computedTotal, 80, accuracy: 0.01)
    }

    func test_computedTotal_neverNegative() {
        let vm = makeSut()
        vm.addLineItem()
        vm.lineItems[0].unitPrice = 10
        vm.cartDiscount = 999
        XCTAssertEqual(vm.computedTotal, 0, accuracy: 0.01)
    }

    func test_isValid_falseWhenLineItemDescriptionEmpty() {
        let vm = makeSut()
        vm.customerId = 1
        vm.addLineItem()
        vm.lineItems[0].description = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWhenLineItemsAllValid() {
        let vm = makeSut()
        vm.customerId = 1
        vm.addLineItem()
        vm.lineItems[0].description = "Screen replacement"
        vm.lineItems[0].unitPrice = 75
        XCTAssertTrue(vm.isValid)
    }

    func test_restoreDraft_restoresLineItems() {
        let vm = makeSut()
        let lineItemDraft = InvoiceDraft.LineItemDraft(description: "Battery", quantity: 2, unitPrice: 49.99)
        let draft = InvoiceDraft(
            customerId: "3",
            lineItems: [lineItemDraft]
        )
        vm._pendingDraft = draft
        vm._draftRecord = DraftRecord(screen: "invoice.create", entityId: nil, updatedAt: Date(), bytes: 10)

        vm.restoreDraft()

        XCTAssertEqual(vm.lineItems.count, 1)
        XCTAssertEqual(vm.lineItems[0].description, "Battery")
        XCTAssertEqual(vm.lineItems[0].quantity, 2)
        XCTAssertEqual(vm.lineItems[0].unitPrice, 49.99, accuracy: 0.001)
    }

    func test_currentDraft_capturesLineItems() {
        let vm = makeSut()
        vm.customerId = 1
        vm.addLineItem()
        vm.lineItems[0].description = "Repair labor"
        vm.lineItems[0].unitPrice = 60

        let draft = vm.currentDraft()

        XCTAssertEqual(draft.lineItems.count, 1)
        XCTAssertEqual(draft.lineItems[0].description, "Repair labor")
        XCTAssertEqual(draft.lineItems[0].unitPrice, 60, accuracy: 0.01)
    }
}
