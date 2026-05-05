import XCTest
@testable import Customers
import Networking

// §5 Customer Groups & Tags — GroupDetailViewModel unit tests

@MainActor
final class GroupDetailViewModelTests: XCTestCase {

    // MARK: - load()

    func test_load_success_populatesGroupAndMembers() async {
        let group = CustomerGroup.stub(id: 7, name: "Premium", memberCountCache: 3)
        let members = [
            CustomerGroupMember.stub(memberId: 1, customerId: 10, firstName: "Alice"),
            CustomerGroupMember.stub(memberId: 2, customerId: 11, firstName: "Bob"),
        ]
        let detail = CustomerGroupDetail.stub(group: group, members: members)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 7)

        await vm.load()

        XCTAssertEqual(vm.group?.id, 7)
        XCTAssertEqual(vm.members.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_failure_setsErrorMessage() async {
        let repo = GroupStubRepository(detailResult: .failure(StubGroupError("not found")))
        let vm = GroupDetailViewModel(repo: repo, groupId: 99)

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.group)
    }

    // MARK: - canManageMembers

    func test_canManageMembers_staticGroup_isTrue() async {
        let group = CustomerGroup.stub(isDynamic: false)
        let detail = CustomerGroupDetail.stub(group: group)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: group.id)
        await vm.load()

        XCTAssertTrue(vm.canManageMembers)
    }

    func test_canManageMembers_dynamicGroup_isFalse() async {
        let group = CustomerGroup.stub(isDynamic: true)
        let detail = CustomerGroupDetail.stub(group: group)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: group.id)
        await vm.load()

        XCTAssertFalse(vm.canManageMembers)
    }

    // MARK: - removeMember()

    func test_removeMember_success_removesMemberFromList() async {
        let group = CustomerGroup.stub(memberCountCache: 2)
        let members = [
            CustomerGroupMember.stub(memberId: 1, customerId: 10),
            CustomerGroupMember.stub(memberId: 2, customerId: 11),
        ]
        let detail = CustomerGroupDetail.stub(group: group, members: members, total: 2)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.removeMember(customerId: 10)

        XCTAssertEqual(vm.members.count, 1)
        XCTAssertEqual(vm.members[0].customerId, 11)
        XCTAssertNil(vm.errorMessage)
    }

    func test_removeMember_decrementsGroupMemberCountCache() async {
        let group = CustomerGroup.stub(memberCountCache: 3)
        let members = [CustomerGroupMember.stub(memberId: 1, customerId: 10)]
        let detail = CustomerGroupDetail.stub(group: group, members: members, total: 3)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.removeMember(customerId: 10)

        XCTAssertEqual(vm.group?.memberCountCache, 2)
    }

    func test_removeMember_failure_setsErrorMessage() async {
        let group = CustomerGroup.stub()
        let members = [CustomerGroupMember.stub(memberId: 1, customerId: 10)]
        let detail = CustomerGroupDetail.stub(group: group, members: members)
        let repo = GroupStubRepository(
            detailResult: .success(detail),
            removeMemberError: StubGroupError("permission denied")
        )
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.removeMember(customerId: 10)

        XCTAssertNotNil(vm.errorMessage)
        // Member should remain (remove failed)
        XCTAssertEqual(vm.members.count, 1)
    }

    func test_removeMember_dynamicGroup_isNoOp() async {
        let group = CustomerGroup.stub(isDynamic: true)
        let members = [CustomerGroupMember.stub(memberId: 1, customerId: 10)]
        let detail = CustomerGroupDetail.stub(group: group, members: members)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.removeMember(customerId: 10)

        // No API call made, member still there
        let callCount = await repo.removeMemberCallCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(vm.members.count, 1)
    }

    // MARK: - addMembers()

    func test_addMembers_success_reloadsDetail() async {
        let detail = CustomerGroupDetail.stub()
        let repo = GroupStubRepository(
            detailResult: .success(detail),
            addMembersResult: .success(.stub(added: 2))
        )
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.addMembers(customerIds: [20, 21])

        let addCount = await repo.addMembersCallCount
        XCTAssertEqual(addCount, 1)
        let addedIds = await repo.lastAddedCustomerIds
        XCTAssertEqual(addedIds, [20, 21])
    }

    func test_addMembers_emptyList_isNoOp() async {
        let repo = GroupStubRepository()
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)

        await vm.addMembers(customerIds: [])

        let callCount = await repo.addMembersCallCount
        XCTAssertEqual(callCount, 0)
    }

    func test_addMembers_failure_setsErrorMessage() async {
        let detail = CustomerGroupDetail.stub()
        let repo = GroupStubRepository(
            detailResult: .success(detail),
            addMembersResult: .failure(StubGroupError("quota exceeded"))
        )
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        await vm.addMembers(customerIds: [20])

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Pagination helpers

    func test_hasMorePages_whenPagesExceedCurrentPage_isTrue() async {
        let pag = GroupMemberPagination(page: 1, limit: 50, total: 100, pages: 2)
        let detail = CustomerGroupDetail(
            group: .stub(),
            members: [.stub()],
            pagination: pag
        )
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        XCTAssertTrue(vm.hasMorePages)
    }

    func test_hasMorePages_whenOnLastPage_isFalse() async {
        let pag = GroupMemberPagination(page: 1, limit: 50, total: 1, pages: 1)
        let detail = CustomerGroupDetail(
            group: .stub(),
            members: [.stub()],
            pagination: pag
        )
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        XCTAssertFalse(vm.hasMorePages)
    }

    // MARK: - Immutability

    func test_removeMember_doesNotMutateOriginalMembersArray() async {
        let members = [
            CustomerGroupMember.stub(memberId: 1, customerId: 10),
            CustomerGroupMember.stub(memberId: 2, customerId: 11),
        ]
        let detail = CustomerGroupDetail.stub(members: members)
        let repo = GroupStubRepository(detailResult: .success(detail))
        let vm = GroupDetailViewModel(repo: repo, groupId: 1)
        await vm.load()

        let snapshot = vm.members

        await vm.removeMember(customerId: 10)

        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(vm.members.count, 1)
    }
}
