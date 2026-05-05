import Testing
import Foundation
@testable import Pos
import Persistence
import Sync

// MARK: - OfflineSaleQueueViewModelTests
//
// These tests exercise the OfflineSaleQueueViewModel without a live GRDB
// database by asserting on the domain-filter logic applied to the raw
// SyncQueueRecord list. The SyncQueueStore.shared actor is not touched;
// instead we verify ViewModel behaviour via the filtering predicate.

@Suite("OfflineSaleQueueViewModel — domain filtering")
struct OfflineSaleQueueViewModelTests {

    // MARK: - Helpers

    /// Build a SyncQueueRecord with a given entity + op.
    private func makeRecord(entity: String, op: String) -> SyncQueueRecord {
        SyncQueueRecord(op: op, entity: entity, payload: "{}")
    }

    @Test("filters in pos.sale.finalize records")
    func filtersInFinalizeSale() {
        let record = makeRecord(entity: "pos", op: "sale.finalize")
        #expect(OfflineSaleQueueViewModel.isPosRecord(record) == true)
    }

    @Test("filters in pos.return.create records")
    func filtersInReturnCreate() {
        let record = makeRecord(entity: "pos", op: "return.create")
        #expect(OfflineSaleQueueViewModel.isPosRecord(record) == true)
    }

    @Test("filters in pos.cash.opening records")
    func filtersInCashOpening() {
        let record = makeRecord(entity: "pos", op: "cash.opening")
        #expect(OfflineSaleQueueViewModel.isPosRecord(record) == true)
    }

    @Test("filters out tickets.create records")
    func filtersOutTickets() {
        let record = makeRecord(entity: "tickets", op: "create")
        #expect(OfflineSaleQueueViewModel.isPosRecord(record) == false)
    }

    @Test("filters out inventory.update records")
    func filtersOutInventory() {
        let record = makeRecord(entity: "inventory", op: "update")
        #expect(OfflineSaleQueueViewModel.isPosRecord(record) == false)
    }

    @Test("filters out records with empty entity and op")
    func filtersOutEmptyEntityAndOp() {
        let emptyEntity = SyncQueueRecord(op: "", entity: "", payload: "{}")
        #expect(OfflineSaleQueueViewModel.isPosRecord(emptyEntity) == false)
    }

    // MARK: - ViewModel initial state

    @Test("initial state: no ops loaded, not loading")
    @MainActor
    func initialState() {
        let vm = OfflineSaleQueueViewModel()
        #expect(vm.ops.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - ViewModel filter integration

    @Test("pos-prefixed ops count matches expected after filter")
    func filterIntegration() {
        let all: [SyncQueueRecord] = [
            makeRecord(entity: "pos", op: "sale.finalize"),
            makeRecord(entity: "pos", op: "return.create"),
            makeRecord(entity: "tickets", op: "create"),
            makeRecord(entity: "inventory", op: "update"),
            makeRecord(entity: "pos", op: "cash.opening"),
        ]
        let posOnly = all.filter { OfflineSaleQueueViewModel.isPosRecord($0) }
        #expect(posOnly.count == 3)
    }
}

// MARK: - CartViewModel offline checkout tests

@Suite("CartViewModel — offline checkout")
struct CartViewModelOfflineTests {

    @MainActor
    @Test("checkoutState starts as idle")
    func initialCheckoutState() {
        let vm = CartViewModel()
        #expect(vm.checkoutState == .idle)
    }

    @MainActor
    @Test("toastMessage starts as nil")
    func initialToastMessage() {
        let vm = CartViewModel()
        #expect(vm.toastMessage == nil)
    }
}
