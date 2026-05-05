import Foundation
import Observation
import Networking
import Core

// MARK: - EmployeeDetailViewModel
//
// Drives EmployeeDetailView. Loads:
//   GET /api/v1/employees/:id            → EmployeeDetail (profile + clock + commissions)
//   GET /api/v1/employees/:id/performance → EmployeePerformance (tickets / revenue)
//   GET /api/v1/roles                     → [RoleRow] (role picker)
//
// Mutations:
//   PUT /api/v1/roles/users/:userId/role  → role assignment (admin only, needs confirm)
//   PUT /api/v1/settings/users/:id        → deactivate / reactivate (admin only)

@MainActor
@Observable
public final class EmployeeDetailViewModel {

    // MARK: - Load state

    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: - Published state

    public private(set) var loadState: LoadState = .idle
    public private(set) var detail: EmployeeDetail?
    public private(set) var performance: EmployeePerformance?
    public private(set) var availableRoles: [RoleRow] = []
    public private(set) var actionState: LoadState = .idle
    /// §14.2 Schedule — upcoming shifts (next 14 days).
    public private(set) var upcomingShifts: [Shift] = []
    /// §14.2 Schedule — pending / approved time-off for this employee.
    public private(set) var timeOffRequests: [TimeOffRequest] = []

    // MARK: - Confirmation dialogs

    public var pendingRoleId: Int? = nil          // set before confirming role change
    public var showRoleConfirm: Bool = false
    public var showDeactivateConfirm: Bool = false
    public var showReactivateConfirm: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored public let employeeId: Int64
    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        loadState = .loading
        do {
            async let detailFetch    = api.getEmployee(id: employeeId)
            async let perfFetch      = api.getEmployeePerformance(id: employeeId)
            async let rolesFetch     = api.listRoles()
            // §14.2 Schedule: fetch upcoming shifts (next 14 days) + time-off
            let now = ISO8601DateFormatter().string(from: Date())
            let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(14 * 86400))
            async let shiftsFetch    = api.listShifts(userId: employeeId, fromDate: now, toDate: future)
            async let timeOffFetch   = api.listTimeOffRequests(userId: employeeId)

            let (d, p, r, shifts, timeOff) = try await (
                detailFetch, perfFetch, rolesFetch, shiftsFetch, timeOffFetch
            )
            detail = d
            performance = p
            availableRoles = r.filter { $0.isActiveFlag }
            upcomingShifts = shifts.sorted { $0.startAt < $1.startAt }
            timeOffRequests = timeOff.filter { $0.status == .approved || $0.status == .pending }
                .sorted { $0.startDate < $1.startDate }
            loadState = .loaded
        } catch {
            AppLog.ui.error("EmployeeDetail load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Role assignment

    /// Initiates role assignment — sets pendingRoleId and shows confirm dialog.
    public func requestRoleChange(roleId: Int) {
        pendingRoleId = roleId
        showRoleConfirm = true
    }

    /// Confirmed role assignment.
    public func confirmRoleChange() async {
        guard let roleId = pendingRoleId else { return }
        actionState = .loading
        do {
            try await api.assignEmployeeRole(userId: employeeId, roleId: roleId)
            // Reload to reflect updated role in UI.
            await load()
            actionState = .loaded
        } catch {
            AppLog.ui.error("Role assignment failed: \(error.localizedDescription, privacy: .public)")
            actionState = .failed(error.localizedDescription)
        }
        pendingRoleId = nil
        showRoleConfirm = false
    }

    // MARK: - Deactivate / reactivate

    public func confirmDeactivate() async {
        actionState = .loading
        showDeactivateConfirm = false
        do {
            let updated = try await api.setEmployeeActive(id: employeeId, isActive: false)
            // Merge new isActive into existing detail (immutable update).
            if let existing = detail {
                detail = updatedDetail(existing, isActive: updated.isActive ?? 0)
            }
            actionState = .loaded
        } catch {
            AppLog.ui.error("Employee deactivate failed: \(error.localizedDescription, privacy: .public)")
            actionState = .failed(error.localizedDescription)
        }
    }

    public func confirmReactivate() async {
        actionState = .loading
        showReactivateConfirm = false
        do {
            let updated = try await api.setEmployeeActive(id: employeeId, isActive: true)
            if let existing = detail {
                detail = updatedDetail(existing, isActive: updated.isActive ?? 1)
            }
            actionState = .loaded
        } catch {
            AppLog.ui.error("Employee reactivate failed: \(error.localizedDescription, privacy: .public)")
            actionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Computed helpers

    /// Commission summary: sum of the 30 most-recent commission records (included in detail).
    public var commissionSummary: Double {
        detail?.commissions?.reduce(0) { $0 + $1.amount } ?? 0
    }

    /// Currently open clock entry if present.
    public var currentShift: ClockEntry? {
        detail?.currentClockEntry
    }

    /// Formatted commission total.
    public var formattedCommissionTotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: commissionSummary)) ?? "$\(commissionSummary)"
    }

    public var isActive: Bool { detail?.active ?? true }

    // MARK: - Private helpers

    /// Returns a new EmployeeDetail with the isActive field replaced.
    /// The struct itself is Decodable-only, so we decode a minimal JSON patch.
    private func updatedDetail(_ existing: EmployeeDetail, isActive: Int) -> EmployeeDetail {
        // Build a minimal JSON dict matching the server shape and decode.
        // This avoids a memberwise init that would break when the server adds fields.
        var dict: [String: Any] = [
            "id": existing.id,
            "is_active": isActive
        ]
        if let v = existing.username   { dict["username"]   = v }
        if let v = existing.email      { dict["email"]      = v }
        if let v = existing.firstName  { dict["first_name"] = v }
        if let v = existing.lastName   { dict["last_name"]  = v }
        if let v = existing.role       { dict["role"]       = v }
        if let v = existing.avatarUrl  { dict["avatar_url"] = v }
        if let v = existing.homeLocationId { dict["home_location_id"] = v }
        if let v = existing.createdAt  { dict["created_at"] = v }
        if let v = existing.permissions { dict["permissions"] = v }
        if let v = existing.isClockedIn { dict["is_clocked_in"] = v }
        // For simplicity we keep commissions / clock_entries nil on the merged
        // copy — a full reload follows for the caller if they need those arrays.
        // EmployeeDetail uses explicit CodingKeys with snake_case keys,
        // so plain JSONDecoder is correct (no convertFromSnakeCase).
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return existing }
        return (try? JSONDecoder().decode(EmployeeDetail.self, from: data)) ?? existing
    }
}
