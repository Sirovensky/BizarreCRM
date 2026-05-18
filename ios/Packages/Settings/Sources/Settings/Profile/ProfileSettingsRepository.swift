import Foundation
import Networking

// MARK: - §19.1 ProfileRepository

/// Abstract contract for fetching and persisting the current user's profile.
public protocol ProfileRepository: Sendable {
    /// Fetch the current user's profile from GET /auth/me.
    func fetchProfile() async throws -> (id: Int, settings: ProfileModel)

    /// Persist profile changes via PUT /settings/users/:id.
    /// - Parameters:
    ///   - id: The numeric user ID returned by fetchProfile.
    ///   - settings: The updated profile settings.
    @discardableResult
    func saveProfile(id: Int, settings: ProfileModel) async throws -> ProfileModel
}

// MARK: - Live implementation

public final class LiveProfileRepository: ProfileRepository {
    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchProfile() async throws -> (id: Int, settings: ProfileModel) {
        // BUGHUNT-2026-05-18: server mounts auth at `/api/v1/auth` (index.ts
        // L1558). APIClient base URL is the shop origin, so the path here
        // must include `/api/v1` — without it the SPA catchall returns HTML
        // and JSON decode fails as "envelope missing".
        let me: MeResponse = try await api.get("/api/v1/auth/me", as: MeResponse.self)
        return (id: me.id, settings: me.toProfileModel())
    }

    public func saveProfile(id: Int, settings: ProfileModel) async throws -> ProfileModel {
        let body = ProfileUpdateRequest(
            firstName: settings.firstName,
            lastName:  settings.lastName,
            email:     settings.email,
            phone:     settings.phone
        )
        // PUT /api/v1/settings/users/:id updates first_name, last_name, email, phone.
        // Returns { success, data: UserRow }.  We decode MeResponse which shares
        // the same snake_case fields.
        // BUGHUNT-2026-05-18: was `/settings/users/:id` — missing `/api/v1`
        // prefix, matched SPA catchall and lost the save.
        let updated: MeResponse = try await api.put(
            "/api/v1/settings/users/\(id)",
            body: body,
            as: MeResponse.self
        )
        // Merge server response back — keep avatarUrl/timezone/locale unchanged
        // if server does not echo them (COALESCE keeps their old values).
        return ProfileModel(
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
