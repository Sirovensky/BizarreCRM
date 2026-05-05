import Foundation
import Networking

// MARK: - §2.5 Change PIN endpoint

public extension APIClient {
    /// POST `/api/v1/auth/change-pin`
    func changePIN(currentPin: String, newPin: String) async throws {
        _ = try await post(
            "/api/v1/auth/change-pin",
            body: ChangePINBody(currentPin: currentPin, newPin: newPin),
            as: ChangePINEmpty.self
        )
    }
}

private struct ChangePINBody: Encodable, Sendable {
    let currentPin: String
    let newPin: String
}

private struct ChangePINEmpty: Decodable, Sendable {}
