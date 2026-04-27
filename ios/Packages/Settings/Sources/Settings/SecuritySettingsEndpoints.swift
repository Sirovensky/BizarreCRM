import Foundation
import Core

// MARK: - APIClient + Security settings endpoints (§19.2)
//
// Named *Endpoints.swift so the §32 sdk-ban lint exempts these call sites.
// All direct API calls from §19.2 security ViewModels must flow through here.
//
// Routes grounded against packages/server/src/routes/auth.routes.ts:
//   GET    /auth/sessions                → list active sessions
//   DELETE /auth/sessions/:id            → revoke one session
//   DELETE /auth/sessions                → revoke all sessions
//   GET    /auth/login-history?limit=N   → recent login events
//   POST   /auth/totp/setup              → initiate TOTP enrollment
//   POST   /auth/totp/verify             → confirm TOTP enrollment
//   GET    /auth/trusted-devices         → list trusted devices
//   POST   /auth/trusted-devices/current → trust current device
//   DELETE /auth/trusted-devices/:id     → revoke trust
//   GET    /settings/organization/logo   → current logo URL
//   POST   /settings/organization/logo   → upload logo (base64 JSON)
//   DELETE /settings/organization/logo   → delete logo
//   GET    /settings/tickets/number-format → ticket number format config
//   PUT    /settings/tickets/number-format → update ticket number format

// MARK: - Active sessions

public extension APIClient {

    func securityListSessions() async throws -> [ActiveSessionWire] {
        try await get("/api/v1/auth/sessions", as: [ActiveSessionWire].self)
    }

    func securityRevokeSession(id: String) async throws {
        try await delete("/api/v1/auth/sessions/\(id)")
    }

    func securityRevokeAllSessions() async throws {
        try await delete("/api/v1/auth/sessions")
    }
}

// MARK: - Login history

public extension APIClient {

    func securityLoginHistory(limit: Int = 50) async throws -> [LoginRecordWire] {
        try await get("/api/v1/auth/login-history?limit=\(limit)", as: [LoginRecordWire].self)
    }
}

// MARK: - TOTP enrollment

private struct TotpSetupBody: Encodable, Sendable {}
private struct TotpVerifyBody: Encodable, Sendable { let secret: String; let code: String }

public extension APIClient {

    func securityTotpSetup() async throws -> TOTPSetupWire {
        try await post("/api/v1/auth/totp/setup", body: TotpSetupBody(), as: TOTPSetupWire.self)
    }

    func securityTotpVerify(secret: String, code: String) async throws {
        _ = try await post("/api/v1/auth/totp/verify", body: TotpVerifyBody(secret: secret, code: code), as: EmptyResponse.self)
    }
}

// MARK: - Trusted devices

private struct TrustCurrentBody: Encodable, Sendable {}

public extension APIClient {

    func securityListTrustedDevices() async throws -> [TrustedDeviceWire] {
        try await get("/api/v1/auth/trusted-devices", as: [TrustedDeviceWire].self)
    }

    func securityTrustCurrentDevice() async throws {
        _ = try await post("/api/v1/auth/trusted-devices/current", body: TrustCurrentBody(), as: EmptyResponse.self)
    }

    func securityRevokeTrustedDevice(id: String) async throws {
        try await delete("/api/v1/auth/trusted-devices/\(id)")
    }
}

// MARK: - Organization logo

private struct LogoUploadBody: Encodable, Sendable {
    let imageBase64: String
    let mimeType: String
    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
    }
}

public extension APIClient {

    func settingsGetLogoURL() async throws -> LogoURLWire {
        try await get("/api/v1/settings/organization/logo", as: LogoURLWire.self)
    }

    func settingsUploadLogo(_ imageData: Data, mimeType: String = "image/jpeg") async throws -> LogoURLWire {
        let body = LogoUploadBody(imageBase64: imageData.base64EncodedString(), mimeType: mimeType)
        return try await post("/api/v1/settings/organization/logo", body: body, as: LogoURLWire.self)
    }

    func settingsDeleteLogo() async throws {
        try await delete("/api/v1/settings/organization/logo")
    }
}

// MARK: - Ticket number format

private struct TicketNumberFormatBody: Encodable, Sendable {
    let format: String
    let seqReset: String
    enum CodingKeys: String, CodingKey { case format; case seqReset = "seq_reset" }
}

public extension APIClient {

    func settingsGetTicketNumberFormat() async throws -> TicketNumberFormatWire {
        try await get("/api/v1/settings/tickets/number-format", as: TicketNumberFormatWire.self)
    }

    func settingsPutTicketNumberFormat(format: String, seqReset: String) async throws -> TicketNumberFormatWire {
        let body = TicketNumberFormatBody(format: format, seqReset: seqReset)
        return try await put("/api/v1/settings/tickets/number-format", body: body, as: TicketNumberFormatWire.self)
    }
}

// MARK: - Wire types (shared)

/// Wire type for session list — used by both ActiveSessionsPage and Endpoints.
public struct ActiveSessionWire: Decodable, Sendable {
    public let id: String
    public let deviceName: String
    public let deviceModel: String
    public let ipAddress: String
    public let location: String?
    public let lastSeenAt: Date
    public let isCurrentDevice: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case ipAddress = "ip_address"
        case location
        case lastSeenAt = "last_seen_at"
        case isCurrentDevice = "is_current_device"
    }
}

/// Wire type for login history.
public struct LoginRecordWire: Decodable, Sendable {
    public let id: String
    public let outcome: String
    public let ipAddress: String
    public let userAgent: String
    public let occurredAt: Date
    public let location: String?
    enum CodingKeys: String, CodingKey {
        case id
        case outcome
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case occurredAt = "occurred_at"
        case location
    }
}

/// Wire type for TOTP setup response.
public struct TOTPSetupWire: Decodable, Sendable {
    public let secret: String
    public let qrURL: String
    public let backupCodes: [String]
    enum CodingKeys: String, CodingKey {
        case secret
        case qrURL = "qr_url"
        case backupCodes = "backup_codes"
    }
}

/// Wire type for trusted devices.
public struct TrustedDeviceWire: Decodable, Sendable {
    public let id: String
    public let deviceName: String
    public let deviceModel: String
    public let trustedAt: Date
    public let expiresAt: Date
    public let isCurrentDevice: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case trustedAt = "trusted_at"
        case expiresAt = "expires_at"
        case isCurrentDevice = "is_current_device"
    }
}

/// Wire type for logo URL.
public struct LogoURLWire: Decodable, Sendable {
    public let url: String?
}

/// Wire type for ticket number format.
public struct TicketNumberFormatWire: Decodable, Sendable {
    public let format: String
    public let seqReset: String
    enum CodingKeys: String, CodingKey { case format; case seqReset = "seq_reset" }
}
