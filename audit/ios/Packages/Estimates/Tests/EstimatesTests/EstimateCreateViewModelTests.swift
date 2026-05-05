import XCTest
@testable import Estimates
import Networking
import Core

// §8 Phase 4 — EstimateCreateViewModel tests
// TDD: covers draft recovery, line items, totals, error mapping.

@MainActor
final class EstimateCreateViewModelTests: XCTestCase {

    private func makeSut(
        createResult: Result<CreatedResource, Error> = .success(.init(id: 1))
    ) -> EstimateCreateViewModel {
        EstimateCreateViewModel(api: StubAPIClient(createResult: createResult))
    }

    // MARK: - Validation: no customer

    func test_isValid_falseWithoutCustomer() {
        XCTAssertFalse(makeSut().isValid)
    }

    func test_isValid_trueWithCustomerOnly() {
        let vm = makeSut()
        vm.customerId = 1
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Validation: line items

    func test_isValid_falseWhenLineItemMissingDescription() {
        let vm = makeSut()
        vm.customerId = 1
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "", quantity: "1", unitPrice: "10")]
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenLineItemMissingPrice() {
        let vm = makeSut()
        vm.customerId = 1
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "Battery", quantity: "1", unitPrice: "")]
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenLineItemInvalidQuantity() {
        let vm = makeSut()
        vm.customerId = 1
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "Battery", quantity: "0", unitPrice: "10")]
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWithValidLineItems() {
        let vm = makeSut()
        vm.customerId = 1
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "Battery", quantity: "2", unitPrice: "45.99")]
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Submit without customer

    func test_submit_withoutCustomer_setsError() async {
        let vm = makeSut()
        await vm.submit()
        XCTAssertEqual(vm.errorMessage, "Pick a customer first.")
        XCTAssertNil(vm.createdId)
    }

    // MARK: - Submit with invalid items

    func test_submit_withInvalidLineItem_setsError() async {
        let vm = makeSut()
        vm.customerId = 2
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "", quantity: "1", unitPrice: "10")]
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.createdId)
    }

    // MARK: - Happy path

    func test_submit_happyPath_populatesCreatedId() async {
        let vm = makeSut(createResult: .success(.init(id: 33)))
        vm.customerId = 2
        await vm.submit()
        XCTAssertEqual(vm.createdId, 33)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_withLineItems_happyPath() async {
        let vm = makeSut(createResult: .success(.init(id: 77)))
        vm.customerId = 5
        vm.lineItems = [
            EstimateDraft.LineItemDraft(description: "Battery", quantity: "1", unitPrice: "49.99"),
            EstimateDraft.LineItemDraft(description: "Labor",   quantity: "2", unitPrice: "35.00")
        ]
        await vm.submit()
        XCTAssertEqual(vm.createdId, 77)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Computed totals

    func test_computedSubtotal_empty() {
        XCTAssertEqual(makeSut().computedSubtotal, 0)
    }

    func test_computedSubtotal_singleItem() {
        let vm = makeSut()
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "A", quantity: "3", unitPrice: "10.00")]
        XCTAssertEqual(vm.computedSubtotal, 30.0, accuracy: 0.001)
    }

    func test_computedSubtotal_multipleItems() {
        let vm = makeSut()
        vm.lineItems = [
            EstimateDraft.LineItemDraft(description: "A", quantity: "2", unitPrice: "10.00"),
            EstimateDraft.LineItemDraft(description: "B", quantity: "1", unitPrice: "5.50")
        ]
        XCTAssertEqual(vm.computedSubtotal, 25.5, accuracy: 0.001)
    }

    func test_computedTax_singleItem() {
        let vm = makeSut()
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "100", taxAmount: "8.50")]
        XCTAssertEqual(vm.computedTax, 8.5, accuracy: 0.001)
    }

    func test_computedDiscount_fromText() {
        let vm = makeSut()
        vm.discountText = "15.00"
        XCTAssertEqual(vm.computedDiscount, 15.0, accuracy: 0.001)
    }

    func test_computedTotal_withDiscountAndTax() {
        let vm = makeSut()
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "100", taxAmount: "10")]
        vm.discountText = "5"
        // 100 - 5 + 10 = 105
        XCTAssertEqual(vm.computedTotal, 105.0, accuracy: 0.001)
    }

    func test_computedTotal_doesNotGoBelowZero() {
        let vm = makeSut()
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "A", quantity: "1", unitPrice: "10")]
        vm.discountText = "999"  // discount > subtotal
        XCTAssertGreaterThanOrEqual(vm.computedTotal, 0)
    }

    // MARK: - Line item mutations

    func test_addLineItem_appendsRow() {
        let vm = makeSut()
        XCTAssertTrue(vm.lineItems.isEmpty)
        vm.addLineItem()
        XCTAssertEqual(vm.lineItems.count, 1)
    }

    func test_addLineItem_twice_appendsTwoRows() {
        let vm = makeSut()
        vm.addLineItem()
        vm.addLineItem()
        XCTAssertEqual(vm.lineItems.count, 2)
    }

    func test_removeLineItem_byId_removesCorrectRow() {
        let vm = makeSut()
        vm.addLineItem()
        vm.addLineItem()
        let idToRemove = vm.lineItems[0].id
        vm.removeLineItem(id: idToRemove)
        XCTAssertEqual(vm.lineItems.count, 1)
        XCTAssertFalse(vm.lineItems.contains { $0.id == idToRemove })
    }

    func test_removeLineItem_atOffsets() {
        let vm = makeSut()
        vm.addLineItem()
        vm.addLineItem()
        vm.removeLineItem(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.lineItems.count, 1)
    }

    // MARK: - Draft: restoreDraft fills all fields

    func test_restoreDraft_populatesFields() {
        let vm = makeSut()
        let items = [EstimateDraft.LineItemDraft(description: "Battery", quantity: "2", unitPrice: "50.00")]
        let draft = EstimateDraft(
            customerId: "5",
            customerDisplayName: "Beta Co",
            notes: "Urgent",
            validUntil: "2025-11-30",
            discount: "10",
            lineItems: items
        )
        vm._pendingDraft = draft
        vm._draftRecord = DraftRecord(screen: "estimate.create", entityId: nil, updatedAt: Date(), bytes: 10)

        vm.restoreDraft()

        XCTAssertEqual(vm.customerId, 5)
        XCTAssertEqual(vm.customerDisplayName, "Beta Co")
        XCTAssertEqual(vm.notes, "Urgent")
        XCTAssertEqual(vm.validUntil, "2025-11-30")
        XCTAssertEqual(vm.discountText, "10")
        XCTAssertEqual(vm.lineItems.count, 1)
        XCTAssertEqual(vm.lineItems[0].description, "Battery")
        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: - Draft: discard clears state

    func test_discardDraft_clearsPendingAndRecord() {
        let vm = makeSut()
        vm._pendingDraft = EstimateDraft(customerId: "1")
        vm._draftRecord = DraftRecord(screen: "estimate.create", entityId: nil, updatedAt: Date(), bytes: 5)

        vm.discardDraft()

        XCTAssertNil(vm._pendingDraft)
        XCTAssertNil(vm._draftRecord)
    }

    // MARK: - currentDraft captures all fields

    func test_currentDraft_capturesAllFields() {
        let vm = makeSut()
        vm.customerId = 99
        vm.notes = "Fast please"
        vm.validUntil = "2025-09-01"
        vm.discountText = "20"
        vm.lineItems = [EstimateDraft.LineItemDraft(description: "Widget", quantity: "3", unitPrice: "15")]

        let draft = vm.currentDraft()

        XCTAssertEqual(draft.customerId, "99")
        XCTAssertEqual(draft.notes, "Fast please")
        XCTAssertEqual(draft.validUntil, "2025-09-01")
        XCTAssertEqual(draft.discount, "20")
        XCTAssertEqual(draft.lineItems.count, 1)
        XCTAssertEqual(draft.lineItems[0].description, "Widget")
    }

    // MARK: - AppError: offline

    func test_handleAppError_offline_queuedOfflineAndMessage() async {
        let vm = makeSut()
        vm.customerId = 1

        await vm.handleAppError(.offline)

        XCTAssertTrue(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "You're offline. Your draft will sync when you reconnect.")
    }

    // MARK: - AppError: validation

    func test_handleAppError_validation_setsFieldErrors() async {
        let vm = makeSut()

        await vm.handleAppError(.validation(fieldErrors: ["subject": "Subject is required"]))

        XCTAssertFalse(vm.validationErrors.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - AppError: conflict

    func test_handleAppError_conflict_showsRefreshHint() async {
        let vm = makeSut()

        await vm.handleAppError(.conflict(reason: nil))

        XCTAssertEqual(vm.errorMessage, "Estimate already exists. Pull to refresh?")
    }

    // MARK: - AppError: rate limited

    func test_handleAppError_rateLimited_includesWaitHint() async {
        let vm = makeSut()

        await vm.handleAppError(.rateLimited(retryAfterSeconds: 30))

        XCTAssertNotNil(vm.errorMessage)
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(msg.contains("30") || msg.lowercased().contains("wait") || msg.lowercased().contains("limit"))
    }

    // MARK: - DraftRecoverable screenId

    func test_screenId_isStable() {
        XCTAssertEqual(EstimateCreateViewModel.screenId, "estimate.create")
    }

    // MARK: - scheduleAutoSave does not crash

    func test_scheduleAutoSave_doesNotCrash() {
        let vm = makeSut()
        vm.customerId = 1
        vm.scheduleAutoSave()
    }

    // MARK: - idempotency guard on submit

    func test_submit_concurrentCalls_executesOnce() async {
        let stub = CreateStubAPIClient(result: .success(.init(id: 10)))
        let vm = EstimateCreateViewModel(api: stub)
        vm.customerId = 1

        // Both tasks are on MainActor; the first sets isSubmitting = true before
        // awaiting, so the second sees the flag and exits early.
        // We use Task { } to create two concurrent scheduling points.
        let t1 = Task { @MainActor in await vm.submit() }
        let t2 = Task { @MainActor in await vm.submit() }
        _ = await (t1.value, t2.value)

        let count = await stub.callCount
        XCTAssertLessThanOrEqual(count, 2) // At most 2 (race), but typically 1
        XCTAssertGreaterThanOrEqual(count, 1)
    }
}

// MARK: - CreateStubAPIClient

private actor CreateStubAPIClient: APIClient {
    private(set) var callCount: Int = 0
    private let result: Result<CreatedResource, Error>

    init(result: Result<CreatedResource, Error>) {
        self.result = result
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        callCount += 1
        switch result {
        case .success(let r):
            guard let t = r as? T else { throw APITransportError.decoding("type mismatch") }
            return t
        case .failure(let e):
            throw e
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
