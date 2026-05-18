import Foundation
import Observation
import Core

// §5 Customer Groups & Tags — group list ViewModel

@MainActor
@Observable
public final class GroupListViewModel {

    // MARK: - State

    public private(set) var groups: [CustomerGroup] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Create sheet state

    public var showingCreate: Bool = false
    public var newGroupName: String = ""
    public var newGroupDescription: String = ""
    public private(set) var isCreating: Bool = false
    public private(set) var createError: String?

    // MARK: - Dependencies

    @ObservationIgnored private let repo: CustomerGroupsRepository

    // MARK: - Init

    public init(repo: CustomerGroupsRepository) {
        self.repo = repo
    }

    // MARK: - Load

    public func load() async {
        if groups.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            groups = try await repo.listGroups()
        } catch let e where AppError.isCancellation(e) {
            return  // BUGHUNT-2026-05-18: nav cancel — .task re-fires on reopen
        } catch {
            AppLog.ui.error("Group list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await load()
    }

    // MARK: - Create

    public func submitCreate() async {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            createError = "Group name is required."
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }

        let description = newGroupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = CreateGroupRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            isDynamic: false
        )
        do {
            let created = try await repo.createGroup(req)
            groups = [created] + groups
            showingCreate = false
            newGroupName = ""
            newGroupDescription = ""
        } catch let e where AppError.isCancellation(e) {
            // User dismissed the create sheet mid-POST. Don't paint
            // "cancelled" as an error AND don't clear the form — the
            // user may want to reopen and try again. Server-side
            // idempotency on /customer-groups isn't guaranteed, so a
            // duplicate group is possible if the user retries; warn
            // via a debug log so we can investigate if it shows up.
            AppLog.ui.debug("Group create cancelled mid-POST — may have created a duplicate row")
        } catch {
            AppLog.ui.error("Group create failed: \(error.localizedDescription, privacy: .public)")
            createError = error.localizedDescription
        }
    }

    public func cancelCreate() {
        showingCreate = false
        newGroupName = ""
        newGroupDescription = ""
        createError = nil
    }

    // MARK: - Delete

    public func deleteGroup(id: Int64) async {
        do {
            try await repo.deleteGroup(id: id)
            groups = groups.filter { $0.id != id }
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: DELETE may have committed; retap 404s.
            return
        } catch {
            AppLog.ui.error("Group delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
