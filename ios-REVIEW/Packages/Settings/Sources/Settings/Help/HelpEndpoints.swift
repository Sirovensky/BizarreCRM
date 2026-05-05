import Foundation
import Networking

// MARK: - HelpEndpoints
//
// APIClient extensions for the Settings Help surface.
// Keeps §20 APIClient containment: ViewModels call these, not api.get() directly.

// MARK: - DTOs

public struct SupportContactDTO: Decodable, Sendable {
    public let email: String
    public let name: String?
}

// ChangelogEntry is declared in WhatsNewHelpView.swift (public, Decodable).
// We reference it from the extension below without redeclaring.

// MARK: - APIClient extensions

public extension APIClient {

    /// `GET /tenants/me/support-contact` — resolve the tenant's support email.
    func fetchSupportContact() async throws -> SupportContactDTO {
        try await get("/tenants/me/support-contact", as: SupportContactDTO.self)
    }

    /// `GET /app/changelog?version=X.Y.Z` — fetch release notes for a given version.
    func fetchChangelog(version: String) async throws -> [ChangelogEntry] {
        let query = [URLQueryItem(name: "version", value: version)]
        return try await get("/app/changelog", query: query, as: [ChangelogEntry].self)
    }
}
