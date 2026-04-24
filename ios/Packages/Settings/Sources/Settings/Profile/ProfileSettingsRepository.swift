import Foundation
import Networking

// MARK: - §19.1 ProfileSettingsRepository

/// Abstract contract for fetching and persisting the current user's profile.
public protocol ProfileSettingsRepository: Sendable {
    /// Fetch the current user's profile from GET /auth/me.
    func fetchProfile() async throws -> (id: Int, settings: ProfileSettings)

    /// Persist profile changes via PUT /settings/users/:id.
    /// - Parameters:
    ///   - id: The numeric user ID returned by fetchProfile.
    ///   - settings: The updated profile settings.
    @discardableResult
    func saveProfile(id: Int, settings: ProfileSettings) async throws -> ProfileSettings
}

// MARK: - Live implementation

public final class LiveProfileSettingsRepository: ProfileSettingsRepository {
    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchProfile() async throws -> (id: Int, settings: ProfileSettings) {
        let me: MeResponse = try await api.get("/auth/me", as: MeResponse.self)
        return (id: me.id, settings: me.toProfileSettings())
    }

    public func saveProfile(id: Int, settings: ProfileSettings) async throws -> ProfileSettings {
        let body = ProfileUpdateRequest(
            firstName: settings.firstName,
            lastName:  settings.lastName,
            email:     settings.email,
            phone:     settings.phone
        )
        // PUT /settings/users/:id updates first_name, last_name, email, phone.
        // Returns { success, data: UserRow }.  We decode MeResponse which shares
        // the same snake_case fields.
        let updated: MeResponse = try await api.put(
            "/settings/users/\(id)",
            body: body,
            as: MeResponse.self
        )
        // Merge server response back — keep avatarUrl/timezone/locale unchanged
        // if server does not echo them (COALESCE keeps their old values).
        return ProfileSettings(
            firstName: updated.firstName ?? settings.firstName,
            lastName:  updated.lastName  ?? settings.lastName,
            email:     updated.email     ?? settings.email,
            phone:     updated.phone     ?? settings.phone,
            avatarUrl: updated.avatarUrl ?? settings.avatarUrl,
            timezone:  updated.timezone  ?? settings.timezone,
            locale:    updated.locale    ?? settings.locale
        )
    }
}
