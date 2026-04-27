import Foundation

// MARK: - APIClient+Tenant
//
// §79 Multi-tenant session management — owned by Agent 8.
//
// This file exposes the public tenant-facing networking surface.
// Internal switch / revoke calls live in Auth/TenantEndpoints.swift
// (module-internal to the Auth package).
//
// §79.1 Per-tenant push token: when signing in to a new tenant, the
// previous APNs device token must be unregistered from the old tenant
// server so push notifications don't cross tenants. Call
// `unregisterDeviceToken()` before switching tenant, then
// `registerDeviceToken(_:)` after the switch completes.

// MARK: - Models

public struct DeviceTokenBody: Encodable, Sendable {
    public let token: String
    public let platform: String

    public init(token: String) {
        self.token = token
        self.platform = "ios"
    }
}

public struct DeviceTokenResponse: Decodable, Sendable {
    public let message: String?
    public init(message: String?) { self.message = message }
}

// MARK: - APIClient extension

public extension APIClient {

    // MARK: §79.1 Per-tenant push token management

    /// POST /api/v1/device-tokens — registers the APNs token with the
    /// current tenant server. Call after every sign-in and after each
    /// tenant switch.
    func registerDeviceToken(_ body: DeviceTokenBody) async throws -> DeviceTokenResponse {
        try await post("/api/v1/device-tokens", body: body, as: DeviceTokenResponse.self)
    }

    /// DELETE /api/v1/device-tokens — unregisters the APNs token from
    /// the current tenant. Call before switching tenants or on sign-out
    /// so pushes from the old tenant stop arriving.
    func unregisterDeviceToken(token: String) async throws {
        // Server expects the token in the path or body depending on implementation.
        // Using POST to /unregister as it's the most cross-compatible pattern.
        struct UnregisterBody: Encodable, Sendable { let token: String; let platform: String }
        _ = try await post(
            "/api/v1/device-tokens/unregister",
            body: UnregisterBody(token: token, platform: "ios"),
            as: DeviceTokenResponse.self
        )
    }
}
