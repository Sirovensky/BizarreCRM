import Foundation
import Networking

// MARK: - §2.5 PIN reset endpoints

public extension APIClient {

    /// POST `/api/v1/auth/pin-reset-request`
    ///
    /// Triggers a server-side email containing a one-time PIN reset link
    /// sent to the tenant-registered email for `userId`.
    /// The iOS client never sees or handles the link; the user follows it
    /// in a web browser to complete the PIN reset.
    ///
    /// - Parameter userId: The ID of the staff member requesting the reset.
    func pinResetRequest(userId: String) async throws {
        struct Body: Encodable, Sendable { let userId: String }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/pin-reset-request",
            body: Body(userId: userId),
            as: Empty.self
        )
    }

    /// POST `/api/v1/auth/pin-reset-manager`
    ///
    /// Allows a manager to reset any staff member's PIN.
    /// Requires the calling manager's own current credentials as proof.
    ///
    /// - Parameters:
    ///   - staffUserId: The user whose PIN should be reset.
    ///   - managerPin: Manager's current PIN for authorization.
    func managerPinReset(staffUserId: String, managerPin: String) async throws {
        struct Body: Encodable, Sendable {
            let staffUserId: String
            let managerPin: String
        }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/pin-reset-manager",
            body: Body(staffUserId: staffUserId, managerPin: managerPin),
            as: Empty.self
        )
    }
}
