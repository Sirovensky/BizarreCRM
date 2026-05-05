import Foundation

// MARK: - FinancialDashboardAccessControl

/// Client-side guard for Financial Dashboard screens.
/// The server is authoritative; this provides UX-layer enforcement.
///
/// Requires the `owner` role (capability: `financial_dashboard.view`).
/// Any role with the `finance.admin` or `reports.owner` capability also qualifies.
public enum FinancialDashboardAccessControl {

    private static let requiredCapabilities: [String] = [
        "financial_dashboard.view",
        "finance.admin",
        "reports.owner"
    ]

    /// Returns `true` if the role is allowed to view the financial dashboard.
    public static func canAccess(roleCapabilities: Set<String>) -> Bool {
        requiredCapabilities.contains(where: { roleCapabilities.contains($0) })
    }

    /// Returns `true` if `roleName` is the literal "owner" role string (fallback when
    /// no capability set is available — e.g. during offline cold-start).
    public static func canAccessByRoleName(_ roleName: String) -> Bool {
        roleName.lowercased() == "owner"
    }
}
