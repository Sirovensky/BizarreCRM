import Foundation

// MARK: - Employee

/// Canonical domain model for a staff member / system user.
/// Wire DTO: Networking/Endpoints/EmployeesEndpoints.swift (Employee).
public struct Employee: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let username: String?
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let role: EmployeeRole
    public let avatarURL: String?
    public let isActive: Bool
    public let hasPin: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        username: String? = nil,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        role: EmployeeRole = .technician,
        avatarURL: String? = nil,
        isActive: Bool = true,
        hasPin: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.avatarURL = avatarURL
        self.isActive = isActive
        self.hasPin = hasPin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(id)") : parts.joined(separator: " ")
    }

    public var initials: String {
        let f = firstName?.prefix(1).uppercased() ?? ""
        let l = lastName?.prefix(1).uppercased() ?? ""
        let combined = f + l
        if !combined.isEmpty { return combined }
        return String((username ?? "?").prefix(2).uppercased())
    }
}

// MARK: - EmployeeRole

public enum EmployeeRole: String, Codable, CaseIterable, Hashable, Sendable {
    case owner
    case manager
    case technician
    case frontDesk = "front_desk"
    case cashier
    case custom

    public var displayName: String {
        switch self {
        case .owner:      return "Owner"
        case .manager:    return "Manager"
        case .technician: return "Technician"
        case .frontDesk:  return "Front Desk"
        case .cashier:    return "Cashier"
        case .custom:     return "Custom"
        }
    }

    /// Default init from a raw server string; falls back to .custom.
    public init(serverString: String?) {
        self = EmployeeRole(rawValue: serverString ?? "") ?? .custom
    }
}
