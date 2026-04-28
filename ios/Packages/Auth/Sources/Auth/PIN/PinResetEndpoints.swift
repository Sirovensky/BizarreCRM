import Foundation
import Networking

// MARK: - §2.5 PIN reset endpoints

public extension APIClient {

    func pinResetRequest(userId: String) async throws {
        _ = try await post(
            "/api/v1/auth/pin-reset-request",
            body: PinResetRequestBody(userId: userId),
            as: PinResetEmpty.self
        )
    }

    func managerPinReset(staffUserId: String, managerPin: String) async throws {
        _ = try await post(
            "/api/v1/auth/pin-reset-manager",
            body: ManagerPinResetBody(staffUserId: staffUserId, managerPin: managerPin),
            as: PinResetEmpty.self
        )
    }
}

private struct PinResetRequestBody: Encodable, Sendable {
    let userId: String
}

private struct ManagerPinResetBody: Encodable, Sendable {
    let staffUserId: String
    let managerPin: String
}

private struct PinResetEmpty: Decodable, Sendable {}
