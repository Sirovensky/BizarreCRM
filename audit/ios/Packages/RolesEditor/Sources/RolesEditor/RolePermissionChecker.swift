import Foundation

// MARK: - RolePermissionChecker

/// Client-side enforcement helper. Server is authoritative; this is double-defence.
/// Use to conditionally hide or disable UI elements based on the active role.
///
/// Example:
/// ```swift
/// if RolePermissionChecker.has(capability: "tickets.delete", role: currentRole) {
///     Button("Delete") { ... }
/// }
/// ```
public enum RolePermissionChecker {

    /// Returns `true` if the role contains the given capability id.
    public static func has(capability: String, role: Role) -> Bool {
        role.capabilities.contains(capability)
    }

    /// Returns `true` if the role contains ALL of the given capability ids.
    public static func hasAll(capabilities: [String], role: Role) -> Bool {
        capabilities.allSatisfy { role.capabilities.contains($0) }
    }

    /// Returns `true` if the role contains ANY of the given capability ids.
    public static func hasAny(capabilities: [String], role: Role) -> Bool {
        capabilities.contains(where: { role.capabilities.contains($0) })
    }

    /// Returns the subset of capabilities the role actually holds.
    public static func intersection(capabilities: [String], role: Role) -> Set<String> {
        Set(capabilities).intersection(role.capabilities)
    }

    /// Returns all capabilities the role does NOT hold.
    public static func missing(capabilities: [String], role: Role) -> [String] {
        capabilities.filter { !role.capabilities.contains($0) }
    }
}
