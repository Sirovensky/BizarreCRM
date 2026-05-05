import Foundation
import Observation
import Core

// §5 Customer Groups & Tags — group detail ViewModel

@MainActor
@Observable
public final class GroupDetailViewModel {

    // MARK: - State

    public private(set) var group: CustomerGroup?
    public private(set) var members: [CustomerGroupMember] = []
    public private(set) var pagination: GroupMemberPagination?
    public private(set) var isLoading: Bool = false
    public private(set) var isLoadingNextPage: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Remove state

    public private(set) var removingMemberIds: Set<Int64> = []

    // MARK: - Pagination

    private var currentPage: Int = 1
    private let pageSize: Int = 50

    // MARK: - Dependencies

    @ObservationIgnored private let repo: CustomerGroupsRepository
    public let groupId: Int64

    // MARK: - Init

    public init(repo: CustomerGroupsRepository, groupId: Int64) {
        self.repo = repo
        self.groupId = groupId
    }

    // MARK: - Computed

    public var isDynamic: Bool { group?.isDynamic ?? false }
    public var canManageMembers: Bool { !isDynamic }
    public var hasMorePages: Bool {
        guard let p = pagination else { return false }
        return p.page < p.pages
    }

    // MARK: - Load

    public func load() async {
        if group == nil { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        currentPage = 1
        do {
            let detail = try await repo.groupDetail(id: groupId, page: 1, limit: pageSize)
            group = detail.group
            members = detail.members
            pagination = detail.pagination
        } catch {
            AppLog.ui.error("Group detail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await load()
    }

    // MARK: - Pagination

    public func loadNextPageIfNeeded(currentMember: CustomerGroupMember) async {
        guard !isLoadingNextPage, hasMorePages else { return }
        guard let last = members.last, last.id == currentMember.id else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        let nextPage = currentPage + 1
        do {
            let detail = try await repo.groupDetail(id: groupId, page: nextPage, limit: pageSize)
            members = members + detail.members
            pagination = detail.pagination
            currentPage = nextPage
        } catch {
            AppLog.ui.error("Group page load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Remove member

    public func removeMember(customerId: Int64) async {
        guard canManageMembers else { return }
        removingMemberIds = removingMemberIds.union([customerId])
        defer { removingMemberIds = removingMemberIds.subtracting([customerId]) }
        do {
            try await repo.removeMember(groupId: groupId, customerId: customerId)
            members = members.filter { $0.customerId != customerId }
            if var g = group {
                let newCount = max(0, g.memberCountCache - 1)
                group = CustomerGroup(
                    id: g.id,
                    name: g.name,
                    description: g.description,
                    isDynamic: g.isDynamic,
                    memberCountCache: newCount,
                    createdByUserId: g.createdByUserId,
                    createdAt: g.createdAt,
                    updatedAt: g.updatedAt
                )
            }
        } catch {
            AppLog.ui.error("Remove member failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add members (called after picker closes)

    public func addMembers(customerIds: [Int64]) async {
        guard canManageMembers, !customerIds.isEmpty else { return }
        do {
            let result = try await repo.addMembers(groupId: groupId, customerIds: customerIds)
            if result.added > 0 {
                // Reload to get fresh member list with names
                await load()
            }
        } catch {
            AppLog.ui.error("Add members failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
