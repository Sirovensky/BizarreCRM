import Foundation
import Networking

// MARK: - §2.5 Change PIN endpoint

public extension APIClient {
    /// POST `/api/v1/auth/change-pin`
    ///
    /// - Parameters:
    ///   - currentPin: The user's currently enrolled PIN (raw digits).
    ///   - newPin: The new PIN to replace it with (4–6 raw digits).
    func changePIN(currentPin: String, newPin: String) async throws {
        struct Body: Encodable, Sendable {
            let currentPin: String
            let newPin: String
        }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/change-pin",
            body: Body(currentPin: currentPin, newPin: newPin),
            as: Empty.self
        )
    }
}
