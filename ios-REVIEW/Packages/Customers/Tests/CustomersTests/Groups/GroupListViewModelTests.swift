import XCTest
@testable import Customers
import Networking

// §5 Customer Groups & Tags — GroupListViewModel unit tests

@MainActor
final class GroupListViewModelTests: XCTestCase {

    // MARK: - load()

    func test_load_success_populatesGroups() async {
        let groups = [CustomerGroup.stub(id: 1, name: "VIP"), CustomerGroup.stub(id: 2, name: "Gold")]
        let repo = GroupStubRepository(listResult: .success(groups))
        let vm = GroupListViewModel(repo: repo)

        await vm.load()

        XCTAssertEqual(vm.groups.count, 2)
        XCTAssertEqual(vm.groups[0].name, "VIP")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_empty_setsEmptyGroups() async {
        let repo = GroupStubRepository(listResult: .success([]))
        let vm = GroupListViewModel(repo: repo)

        await vm.load()

        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_failure_setsErrorMessage() async {
        let repo = GroupStubRepository(listResult: .failure(StubGroupError("network error")))
        let vm = GroupListViewModel(repo: repo)

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.groups.isEmpty)
    }

    func test_load_clearsErrorOnRetry() async {
        let repo = GroupStubRepository(listResult: .failure(StubGroupError()))
        let vm = GroupListViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        // Now fix the repo and retry
        await repo.updateListResult(.success([.stub()]))
        await vm.load()

        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.groups.isEmpty)
    }

    // MARK: - refresh()

    func test_refresh_callsLoad() async {
        let groups = [CustomerGroup.stub()]
        let repo = GroupStubRepository(listResult: .success(groups))
        let vm = GroupListViewModel(repo: repo)

        await vm.refresh()

        let callCount = await repo.listCallCount
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - submitCreate()

    func test_submitCreate_emptyName_setsCreateError() async {
        let repo = GroupStubRepository()
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "   "

        await vm.submitCreate()

        XCTAssertNotNil(vm.createError)
        let callCount = await repo.createCallCount
        XCTAssertEqual(callCount, 0)
    }

    func test_submitCreate_success_prependsGroupAndResetsState() async {
        let newGroup = CustomerGroup.stub(id: 99, name: "New Group")
        let repo = GroupStubRepository(createResult: .success(newGroup))
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "New Group"
        vm.newGroupDescription = "A desc"
        vm.showingCreate = true

        await vm.submitCreate()

        XCTAssertEqual(vm.groups.first?.id, 99)
        XCTAssertFalse(vm.showingCreate)
        XCTAssertTrue(vm.newGroupName.isEmpty)
        XCTAssertTrue(vm.newGroupDescription.isEmpty)
        XCTAssertNil(vm.createError)
        XCTAssertFalse(vm.isCreating)
    }

    func test_submitCreate_sendsCorrectRequest() async {
        let repo = GroupStubRepository()
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "Loyalty"
        vm.newGroupDescription = "High-value"

        await vm.submitCreate()

        let req = await repo.lastCreateRequest
        XCTAssertEqual(req?.name, "Loyalty")
        XCTAssertEqual(req?.description, "High-value")
        XCTAssertFalse(req?.isDynamic ?? true)
    }

    func test_submitCreate_emptyDescription_sendsNil() async {
        let repo = GroupStubRepository()
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "Group A"
        vm.newGroupDescription = "   "

        await vm.submitCreate()

        let req = await repo.lastCreateRequest
        XCTAssertNil(req?.description)
    }

    func test_submitCreate_failure_setsCreateError() async {
        let repo = GroupStubRepository(createResult: .failure(StubGroupError("server reject")))
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "Group A"

        await vm.submitCreate()

        XCTAssertNotNil(vm.createError)
        XCTAssertTrue(vm.groups.isEmpty)
    }

    // MARK: - cancelCreate()

    func test_cancelCreate_resetsState() {
        let repo = GroupStubRepository()
        let vm = GroupListViewModel(repo: repo)
        vm.newGroupName = "Draft"
        vm.newGroupDescription = "Draft desc"
        vm.showingCreate = true

        vm.cancelCreate()

        XCTAssertFalse(vm.showingCreate)
        XCTAssertTrue(vm.newGroupName.isEmpty)
        XCTAssertTrue(vm.newGroupDescription.isEmpty)
        XCTAssertNil(vm.createError)
    }

    // MARK: - deleteGroup()

    func test_deleteGroup_success_removesFromList() async {
        let groups = [CustomerGroup.stub(id: 1), CustomerGroup.stub(id: 2)]
        let repo = GroupStubRepository(listResult: .success(groups))
        let vm = GroupListViewModel(repo: repo)
        await vm.load()

        await vm.deleteGroup(id: 1)

        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups[0].id, 2)
        let deletedId = await repo.lastDeletedId
        XCTAssertEqual(deletedId, 1)
    }

    func test_deleteGroup_failure_setsErrorMessage() async {
        let groups = [CustomerGroup.stub(id: 1)]
        let repo = GroupStubRepository(
            listResult: .success(groups),
            deleteError: StubGroupError("cannot delete")
        )
        let vm = GroupListViewModel(repo: repo)
        await vm.load()

        await vm.deleteGroup(id: 1)

        XCTAssertNotNil(vm.errorMessage)
        // Group should still be in the list (delete failed)
        XCTAssertEqual(vm.groups.count, 1)
    }

    // MARK: - Immutability

    func test_groups_array_is_replaced_not_mutated() async {
        let initial = [CustomerGroup.stub(id: 1)]
        let repo = GroupStubRepository(listResult: .success(initial))
        let vm = GroupListViewModel(repo: repo)
        await vm.load()

        let snapshot = vm.groups
        let newGroup = CustomerGroup.stub(id: 99, name: "New")
        await repo.updateListResult(.success([newGroup]))
        await vm.refresh()

        // snapshot should be unchanged
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot[0].id, 1)
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups[0].id, 99)
    }
}

// MARK: - GroupStubRepository mutation helpers for tests

extension GroupStubRepository {
    func updateListResult(_ result: Result<[CustomerGroup], Error>) {
        self.listResult = result
    }
}
