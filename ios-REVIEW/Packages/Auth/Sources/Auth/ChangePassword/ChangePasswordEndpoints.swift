import Foundation
import Networking

// MARK: - §2.9 Change password endpoint

public extension APIClient {
    /// POST `/api/v1/auth/change-password`
    func changePassword(currentPassword: String, newPassword: String) async throws {
        _ = try await post(
            "/api/v1/auth/change-password",
            body: ChangePasswordBody(currentPassword: currentPassword, newPassword: newPassword),
            as: ChangePasswordEmpty.self
        )
    }
}

private struct ChangePasswordBody: Encodable, Sendable {
    let currentPassword: String
    let newPassword: String
}

private struct ChangePasswordEmpty: Decodable, Sendable {}
