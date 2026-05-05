import Foundation

// MARK: - Role

public struct Role: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var preset: String?   // nil = custom
    public var capabilities: Set<String>

    public init(id: String, name: String, preset: String? = nil, capabilities: Set<String> = []) {
        self.id = id
        self.name = name
        self.preset = preset
        self.capabilities = capabilities
    }
}

// MARK: - RolesEditorError

public enum RolesEditorError: Error, Sendable, LocalizedError, Equatable {
    case roleNotFound
    case duplicateName
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .roleNotFound:    return "Role not found."
        case .duplicateName:   return "A role with that name already exists."
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let rolesChanged = Notification.Name("com.bizarrecrm.rolesChanged")
}
