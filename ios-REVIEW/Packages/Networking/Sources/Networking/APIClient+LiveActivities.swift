import Foundation
import Core

public extension APIClient {
    /// `POST /api/v1/live-activities/register` — registers an ActivityKit push token.
    func registerLiveActivityPushToken(_ request: LiveActivityPushTokenRequest) async throws {
        _ = try await post(
            "/api/v1/live-activities/register",
            body: request,
            as: DeviceRegisterResponse.self
        )
    }
}
