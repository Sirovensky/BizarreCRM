import Foundation

public struct Customer: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let email: String?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        firstName: String,
        lastName: String,
        phone: String? = nil,
        email: String? = nil,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}
