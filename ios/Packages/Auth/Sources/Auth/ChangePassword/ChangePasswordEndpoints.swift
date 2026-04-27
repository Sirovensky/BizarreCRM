import Foundation
import Networking

// MARK: - §2.9 Change password endpoint

public extension APIClient {
    /// POST `/api/v1/auth/change-password`
    ///
    /// - Parameters:
    ///   - currentPassword: The user's existing password.
    ///   - newPassword: The replacement password (≥ 8 chars, strength validated client-side).
    func changePassword(currentPassword: String, newPassword: String) async throws {
        struct Body: Encodable, Sendable {
            let currentPassword: String
            let newPassword: String
        }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/change-password",
            body: Body(currentPassword: currentPassword, newPassword: newPassword),
            as: Empty.self
        )
    }
}
