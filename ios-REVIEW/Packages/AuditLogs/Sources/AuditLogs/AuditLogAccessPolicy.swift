import Foundation

/// Minimal access-control check for the Audit Logs feature (§50.9).
///
/// Assumption: the app stores the current user's role in
/// `UserDefaults.standard` under key `"current_role"`. Roles "admin" and
/// "owner" are granted `audit.view.all`.  When a proper `RoleStore` with
/// a `capabilities` set lands in the Auth/Settings package, replace
/// `UserDefaults` reads here with `RoleStore.current?.capabilities`.
///
/// This type is intentionally value-based and `Sendable`; it never
/// mutates `UserDefaults`; callers may re-evaluate on each navigation.
public struct AuditLogAccessPolicy: Sendable {

    private static let allowedRoles: Set<String> = ["admin", "owner"]
    private static let roleKey = "current_role"

    /// Returns `true` when the currently logged-in user has `audit.view.all`.
    public static func canViewAuditLogs() -> Bool {
        let role = UserDefaults.standard.string(forKey: roleKey) ?? ""
        return allowedRoles.contains(role.lowercased())
    }

    /// Convenience overload for tests / previews that inject the role directly.
    public static func canViewAuditLogs(role: String) -> Bool {
        allowedRoles.contains(role.lowercased())
    }
}
