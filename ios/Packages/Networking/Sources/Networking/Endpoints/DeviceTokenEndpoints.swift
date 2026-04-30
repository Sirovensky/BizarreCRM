import Foundation
import Core

// MARK: - DTOs

/// Request body for `POST /api/v1/devices/register`.
/// Matches the server contract: `{ deviceToken, deviceType, tenantId }`.
/// (§21.1 / §13.2 push registration)
public struct DeviceRegisterRequest: Encodable, Sendable {
    public let deviceToken: String
    public let deviceType: String
    public let tenantId: String?
    /// Human-readable model string, e.g. "iPhone 15 Pro".
    public let model: String?
    /// e.g. "17.5"
    public let iosVersion: String?
    /// e.g. "1.0.0"
    public let appVersion: String?
    /// IETF locale tag, e.g. "en-US"
    public let locale: String?

    public init(
        deviceToken: String,
        deviceType: String = "ios",
        tenantId: String? = nil,
        model: String? = nil,
        iosVersion: String? = nil,
        appVersion: String? = nil,
        locale: String? = nil
    ) {
        self.deviceToken = deviceToken
        self.deviceType = deviceType
        self.tenantId = tenantId
        self.model = model
        self.iosVersion = iosVersion
        self.appVersion = appVersion
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case deviceToken  = "deviceToken"
        case deviceType   = "deviceType"
        case tenantId     = "tenantId"
        case model
        case iosVersion   = "os_version"
        case appVersion   = "app_version"
        case locale
    }
}

/// Generic acknowledgement response the server sends back.
public struct DeviceRegisterResponse: Decodable, Sendable {
    public let message: String?
    public init(message: String?) { self.message = message }
}

// MARK: - APIClient extension

public extension APIClient {

    /// `POST /api/v1/devices/register` — upload APNs device token.
    func registerDeviceToken(_ request: DeviceRegisterRequest) async throws -> DeviceRegisterResponse {
        try await post("/api/v1/devices/register",
                       body: request,
                       as: DeviceRegisterResponse.self)
    }

    /// `DELETE /api/v1/devices/:token` — unregister on logout.
    func unregisterDeviceToken(_ token: String) async throws {
        try await delete("/api/v1/devices/\(token)")
    }

#if os(iOS)
    /// `POST /api/v1/live-activities/register` — registers an ActivityKit push token.
    func registerLiveActivityPushToken(_ request: LiveActivityPushTokenRequest) async throws {
        _ = try await post(
            "/api/v1/live-activities/register",
            body: request,
            as: DeviceRegisterResponse.self
        )
    }
#endif
}
