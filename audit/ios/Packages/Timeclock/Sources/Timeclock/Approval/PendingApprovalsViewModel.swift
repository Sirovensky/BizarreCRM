import Foundation
import Observation
import Networking
import Core

// MARK: - §14 PendingApprovalsViewModel
//
// Loads all pending clock entries for the manager and groups them per employee.
// Pending = entries with no clock_out (still open), or all entries when the
// manager wants to review everything for a period. Uses the existing
// GET /api/v1/timesheet/clock-entries route (no userId filter → manager sees all).
//
// Approve/reject actions delegate to ApprovalActionViewModel; state is then
// reflected back here via immutable EmployeeGroup replacement.
//
// Bulk approve for an employee calls approve on each pending entry in sequence.

@MainActor
@Observable
public final class PendingApprovalsViewModel {

    // MARK: - Load state

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public enum BulkState: Sendable, Equatable {
        case idle, processing, done, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var groups: [EmployeeGroup] = []
    public private(set) var bulkState: BulkState = .idle

    /// ISO-8601 date filter ("yyyy-MM-dd"). Nil = server default (no lower bound).
    public var fromDate: String? = nil
    /// ISO-8601 date filter ("yyyy-MM-dd"). Nil = server default (no upper bound).
    public var toDate: String? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    /// Fetches all clock entries visible to the manager, then groups by employee.
    public func load() async {
        loadState = .loading
        do {
            let entries = try await api.listClockEntries(
                userId: nil,       // manager sees all employees
                fromDate: fromDate,
                toDate: toDate
            )
            groups = buildGroups(from: entries)
            loadState = .loaded
        } catch {
            AppLog.ui.error(
                "PendingApprovals load failed: \(error.localizedDescription, privacy: .public)"
            )
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Single-entry approve / reject

    /// Approve a single clock entry. Delegates network call to `ApprovalActionViewModel`.
    /// On success, updates the group state immutably.
    public func approve(entry: ClockEntry, extraNote: String = "") async {
        let actionVM = ApprovalActionViewModel(entry: entry, api: api)
        await actionVM.approve(extraNote: extraNote)
        switch actionVM.actionState {
        case .approved:
            applyStatus(.approved, toEntryId: entry.id)
        case let .failed(msg):
            AppLog.ui.error("Single approve failed id=\(entry.id): \(msg, privacy: .public)")
        default:
            break
        }
    }

    /// Reject a single clock entry.
    public func reject(entry: ClockEntry, reason: String) async {
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let actionVM = ApprovalActionViewModel(entry: entry, api: api)
        actionVM.reason = reason
        await actionVM.reject()
        switch actionVM.actionState {
        case .rejected:
            applyStatus(.rejected(reason: reason), toEntryId: entry.id)
        case let .failed(msg):
            AppLog.ui.error("Single reject failed id=\(entry.id): \(msg, privacy: .public)")
        default:
            break
        }
    }

    // MARK: - Bulk approve

    /// Approve all pending entries for a given employee in sequence.
    /// Stops on first network error and surfaces it in `bulkState`.
    public func approveAll(employeeId: Int64) async {
        guard let group = groups.first(where: { $0.employeeId == employeeId }) else { return }
        let pending = group.entries.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }

        bulkState = .processing
        for item in pending {
            let actionVM = ApprovalActionViewModel(entry: item.entry, api: api)
            await actionVM.approve()
            switch actionVM.actionState {
            case .approved:
                applyStatus(.approved, toEntryId: item.entry.id)
            case let .failed(msg):
                bulkState = .failed(msg)
                return
            default:
                break
            }
        }
        bulkState = .done
    }

    // MARK: - Computed helpers

    /// Total number of entries still in `.pending` state across all groups.
    public var totalPendingCount: Int {
        groups.reduce(0) { $0 + $1.pendingCount }
    }

    // MARK: - Private helpers

    /// Groups raw ClockEntry array by userId, wrapping in ApprovalEntry(.pending).
    private func buildGroups(from entries: [ClockEntry]) -> [EmployeeGroup] {
        var byEmployee: [Int64: [ClockEntry]] = [:]
        for entry in entries {
            byEmployee[entry.userId, default: []].append(entry)
        }
        return byEmployee
            .sorted { $0.key < $1.key }
            .map { (userId, empEntries) in
                // Server includes first_name/last_name on the ClockEntry via the
                // JOIN in GET /clock-entries. We surface userId as displayName
                // since ClockEntry DTO only carries userId (names live on Employee).
                let approvalEntries = empEntries
                    .sorted { $0.clockIn > $1.clockIn }
                    .map { ApprovalEntry(entry: $0) }
                return EmployeeGroup(
                    employeeId: userId,
                    displayName: "Employee #\(userId)",
                    entries: approvalEntries
                )
            }
    }

    /// Immutably replaces the ApprovalEntry matching `entryId` with a new status.
    private func applyStatus(_ status: ApprovalStatus, toEntryId id: Int64) {
        groups = groups.map { group in
            guard let target = group.entries.first(where: { $0.id == id }) else {
                return group
            }
            return group.replacing(target.withStatus(status))
        }
    }
}
