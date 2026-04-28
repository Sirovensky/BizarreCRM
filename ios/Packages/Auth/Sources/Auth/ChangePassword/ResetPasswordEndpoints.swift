import Foundation
import Networking

// MARK: - §2.8 Password reset + backup-code recovery endpoints

public extension APIClient {

    // MARK: - POST /auth/reset-password

    func resetPassword(token: String, newPassword: String) async throws {
        _ = try await post(
            "/api/v1/auth/reset-password",
            body: ResetPasswordBody(token: token, password: newPassword),
            as: ResetPasswordEmpty.self
        )
    }

    // MARK: - POST /auth/recover-with-backup-code

    func recoverWithBackupCode(
        username: String,
        password: String,
        backupCode: String
    ) async throws -> BackupCodeRecoveryResponse {
        return try await post(
            "/api/v1/auth/recover-with-backup-code",
            body: BackupCodeRecoveryBody(username: username, password: password, backupCode: backupCode),
            as: BackupCodeRecoveryResponse.self
        )
    }
}

private struct ResetPasswordBody: Encodable, Sendable {
    let token: String
    let password: String
}

private struct ResetPasswordEmpty: Decodable, Sendable {}

private struct BackupCodeRecoveryBody: Encodable, Sendable {
    let username: String
    let password: String
    let backupCode: String
}

// MARK: - BackupCodeRecoveryResponse

public struct BackupCodeRecoveryResponse: Decodable, Sendable {
    public let recoveryToken: String

    public init(recoveryToken: String) {
        self.recoveryToken = recoveryToken
    }

    enum CodingKeys: String, CodingKey {
        case recoveryToken = "recoveryToken"
    }
}
