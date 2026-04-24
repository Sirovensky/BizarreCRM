import Foundation

// MARK: - §19.1 ProfileSettings model

/// Codable model representing the current user's editable profile fields.
/// Decoded from GET /auth/me (envelope: { success, data }).
/// The write path goes through PUT /settings/users/:id (admin-capable callers)
/// or PATCH /auth/me when that endpoint is available.
public struct ProfileSettings: Codable, Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var phone: String
    public var avatarUrl: String?
    public var timezone: String
    public var locale: String

    public init(
        firstName: String = "",
        lastName: String = "",
        email: String = "",
        phone: String = "",
        avatarUrl: String? = nil,
        timezone: String = "",
        locale: String = ""
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.avatarUrl = avatarUrl
        self.timezone = timezone
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName  = "last_name"
        case email
        case phone
        case avatarUrl = "avatar_url"
        case timezone
        case locale
    }
}

// MARK: - Wire types

/// Decoded from GET /auth/me → { success, data: MeResponse }
/// The server injects req.user which includes more fields; we pick only what
/// ProfileSettings needs plus the numeric id required for the PUT route.
public struct MeResponse: Decodable, Sendable {
    public let id: Int
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let avatarUrl: String?
    public let timezone: String?
    public let locale: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName  = "last_name"
        case email
        case phone
        case avatarUrl = "avatar_url"
        case timezone
        case locale
    }

    /// Convert to the domain model, substituting safe defaults for nil fields.
    public func toProfileSettings() -> ProfileSettings {
        ProfileSettings(
            firstName: firstName ?? "",
            lastName:  lastName  ?? "",
            email:     email     ?? "",
            phone:     phone     ?? "",
            avatarUrl: avatarUrl,
            timezone:  timezone  ?? "",
            locale:    locale    ?? ""
        )
    }
}

/// Body for PUT /settings/users/:id — only the fields we allow the user to
/// edit through this screen. All fields are optional so unchanged ones are
/// passed through COALESCE on the server.
public struct ProfileUpdateRequest: Encodable, Sendable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var phone: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName  = "last_name"
        case email
        case phone
    }
}

// MARK: - Validation helpers

extension ProfileSettings {

    public enum ValidationError: LocalizedError, Sendable {
        case firstNameEmpty
        case lastNameEmpty
        case emailInvalid

        public var errorDescription: String? {
            switch self {
            case .firstNameEmpty: return "First name is required."
            case .lastNameEmpty:  return "Last name is required."
            case .emailInvalid:   return "Enter a valid email address."
            }
        }
    }

    /// Returns the first validation error, or nil if the settings are valid.
    public func validationError() -> ValidationError? {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty { return .firstNameEmpty }
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty  { return .lastNameEmpty  }
        if !email.isEmpty && !email.contains("@")                 { return .emailInvalid   }
        return nil
    }
}
