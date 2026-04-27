import Foundation
import Networking

// MARK: - §2.8 Password reset + backup-code recovery endpoints

public extension APIClient {

    // MARK: - POST /auth/reset-password

    /// Complete a password reset.
    /// Reached via Universal Link `app.bizarrecrm.com/reset-password/:token`.
    ///
    /// Server returns 410 when the token is expired or already used.
    func resetPassword(token: String, newPassword: String) async throws {
        struct Body: Encodable, Sendable {
            let token: String
            let password: String
        }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/reset-password",
            body: Body(token: token, password: newPassword),
            as: Empty.self
        )
    }

    // MARK: - POST /auth/recover-with-backup-code

    /// Recover account access using a backup code.
    ///
    /// Returns `{ recoveryToken }`. The caller should push the SetPassword
    /// step using the returned `recoveryToken` as the challengeToken.
    func recoverWithBackupCode(
        username: String,
        password: String,
        backupCode: String
    ) async throws -> BackupCodeRecoveryResponse {
        struct Body: Encodable, Sendable {
            let username: String
            let password: String
            let backupCode: String
        }
        return try await post(
            "/api/v1/auth/recover-with-backup-code",
            body: Body(username: username, password: password, backupCode: backupCode),
            as: BackupCodeRecoveryResponse.self
        )
    }
}

// MARK: - BackupCodeRecoveryResponse

/// Successful response from `POST /auth/recover-with-backup-code`.
public struct BackupCodeRecoveryResponse: Decodable, Sendable {
    /// Used as the `challengeToken` in the subsequent SetPassword step.
    public let recoveryToken: String

    public init(recoveryToken: String) {
        self.recoveryToken = recoveryToken
    }

    enum CodingKeys: String, CodingKey {
        case recoveryToken = "recoveryToken"
    }
}
