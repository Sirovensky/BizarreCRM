import SwiftUI
import DesignSystem

// MARK: - §19 Role-based permission badge helpers

/// Maps a server role string to display metadata for the permission badge
/// shown on Settings → Profile.
///
/// Server role values: "admin" | "manager" | "technician" | "cashier" | "viewer"
/// (custom roles fall through to the `.other` bucket).
public enum RolePermissionBadge {

    // MARK: - Display label

    public static func label(for role: String) -> String {
        switch role.lowercased() {
        case "admin":       return "Admin"
        case "manager":     return "Manager"
        case "technician":  return "Technician"
        case "cashier":     return "Cashier"
        case "viewer":      return "Viewer"
        default:            return role.capitalized
        }
    }

    // MARK: - SF Symbol icon

    public static func icon(for role: String) -> String {
        switch role.lowercased() {
        case "admin":       return "shield.lefthalf.filled"
        case "manager":     return "person.badge.key"
        case "technician":  return "wrench.and.screwdriver"
        case "cashier":     return "creditcard"
        case "viewer":      return "eye"
        default:            return "person.circle"
        }
    }

    // MARK: - Accent color

    public static func color(for role: String) -> Color {
        switch role.lowercased() {
        case "admin":       return .bizarreError
        case "manager":     return .bizarreOrange
        case "technician":  return .bizarreTeal
        case "cashier":     return .bizarreSuccess
        case "viewer":      return .bizarreOnSurfaceMuted
        default:            return .bizarreOnSurface
        }
    }

    // MARK: - Compact access-level label (for the trailing chip)

    public static func accessLevel(for role: String) -> String {
        switch role.lowercased() {
        case "admin":       return "Full access"
        case "manager":     return "Elevated"
        case "technician":  return "Standard"
        case "cashier":     return "POS only"
        case "viewer":      return "Read-only"
        default:            return "Custom"
        }
    }
}
