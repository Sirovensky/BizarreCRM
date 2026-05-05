import Foundation

// MARK: - EmployeeListFilter
//
// Client-side filter state for the employee list.
// The server's GET /api/v1/employees returns active employees only.
// When showInactive = true the list also fetches GET /api/v1/settings/users
// (admin-only endpoint that returns ALL users) and merges.
//
// role: nil = all roles. Non-nil = exact match against Employee.role.
// locationId: nil = all locations.
// showInactive: false = active only (default, uses /employees endpoint).
//               true  = include inactive (uses /settings/users — admin only).
// searchQuery: client-side text filter against displayName + email.

public struct EmployeeListFilter: Equatable, Sendable {

    public var role: String?
    public var locationId: Int64?
    public var showInactive: Bool
    public var searchQuery: String
    /// When true, only show employees that are currently clocked in.
    /// Requires the employee list to contain presence data (`is_clocked_in`).
    /// The employee list screen adds a "Clocked In" link to open `ClockedInNowView`
    /// which handles the presence-aware fetch; this flag is a quick filter hint.
    public var clockedInOnly: Bool

    public init(
        role: String? = nil,
        locationId: Int64? = nil,
        showInactive: Bool = false,
        searchQuery: String = "",
        clockedInOnly: Bool = false
    ) {
        self.role = role
        self.locationId = locationId
        self.showInactive = showInactive
        self.searchQuery = searchQuery
        self.clockedInOnly = clockedInOnly
    }

    public var isDefault: Bool {
        role == nil && locationId == nil && !showInactive && searchQuery.isEmpty && !clockedInOnly
    }
}
