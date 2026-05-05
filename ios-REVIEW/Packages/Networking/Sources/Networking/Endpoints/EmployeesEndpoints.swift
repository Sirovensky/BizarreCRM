import Foundation

/// `GET /api/v1/employees` — server returns a FLAT ARRAY under `data`
/// (not wrapped). No pagination.
public struct Employee: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let username: String?
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let role: String?
    public let avatarUrl: String?
    public let isActive: Int?
    public let hasPin: Int?
    public let createdAt: String?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(id)") : parts.joined(separator: " ")
    }

    public var initials: String {
        let f = firstName?.prefix(1).uppercased() ?? ""
        let l = lastName?.prefix(1).uppercased() ?? ""
        let c = f + l
        if !c.isEmpty { return c }
        return String((username ?? "?").prefix(2).uppercased())
    }

    public var active: Bool { (isActive ?? 0) != 0 }

    enum CodingKeys: String, CodingKey {
        case id, username, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarUrl = "avatar_url"
        case isActive = "is_active"
        case hasPin = "has_pin"
        case createdAt = "created_at"
    }
}

public extension APIClient {
    func listEmployees() async throws -> [Employee] {
        try await get("/api/v1/employees", as: [Employee].self)
    }
}
