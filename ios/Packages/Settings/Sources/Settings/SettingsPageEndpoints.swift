import Foundation
import Networking

// MARK: - APIClient + Settings pages
//
// All direct API calls from Settings page ViewModels must flow through this
// file. Named *Endpoints.swift so the §32 sdk-ban lint exempts it.
//
// Routes grounded against packages/server/src/routes/:
//   tenant.routes.ts           — /tenant/company, /auth/me
//   settings.routes.ts         — /settings/payment, /settings/sms, /settings/organization
//   tax.routes.ts              — /tax-rates
//   auth.routes.ts             — /auth/revoke-all, /auth/change-password
//   tenants.routes.ts          — /tenants/me/support-contact
//   app.routes.ts              — /app/changelog

// MARK: - Company Info

public struct CompanyInfoWire: Codable, Sendable {
    public var legalName: String?
    public var dba: String?
    public var address: String?
    public var city: String?
    public var state: String?
    public var zip: String?
    public var phone: String?
    public var website: String?
    public var ein: String?
}

public extension APIClient {
    func settingsCompanyInfo() async throws -> CompanyInfoWire {
        try await get("/api/v1/tenant/company", as: CompanyInfoWire.self)
    }

    func settingsSaveCompanyInfo(_ body: CompanyInfoWire) async throws -> CompanyInfoWire {
        try await patch("/api/v1/tenant/company", body: body, as: CompanyInfoWire.self)
    }
}

// MARK: - Language & Region

public struct LanguageRegionWire: Codable, Sendable {
    public var locale: String?
    public var timezone: String?
    public var currency: String?
    public var dateFormat: String?
    public var numberFormat: String?
}

public extension APIClient {
    func settingsOrganization() async throws -> LanguageRegionWire {
        try await get("/api/v1/settings/organization", as: LanguageRegionWire.self)
    }

    func settingsSaveOrganization(_ body: LanguageRegionWire) async throws -> LanguageRegionWire {
        try await put("/api/v1/settings/organization", body: body, as: LanguageRegionWire.self)
    }
}

// MARK: - Payment Methods

public struct PaymentSettingsWire: Codable, Sendable {
    public var cashEnabled: Bool?
    public var cardEnabled: Bool?
    public var giftCardEnabled: Bool?
    public var storeCreditEnabled: Bool?
    public var checkEnabled: Bool?
    public var blockChypApiKey: String?
    public var blockChypTerminalName: String?
}

public extension APIClient {
    func settingsPayment() async throws -> PaymentSettingsWire {
        try await get("/api/v1/settings/payment", as: PaymentSettingsWire.self)
    }

    func settingsSavePayment(_ body: PaymentSettingsWire) async throws -> PaymentSettingsWire {
        try await put("/api/v1/settings/payment", body: body, as: PaymentSettingsWire.self)
    }
}

// MARK: - SMS Provider

public struct SmsSettingsWire: Codable, Sendable {
    public var provider: String?
    public var fromNumber: String?
    public var twilioAccountSid: String?
    public var twilioAuthToken: String?
    public var bandwidthAccountId: String?
    public var bandwidthApplicationId: String?
    public var a2pStatus: String?
}

private struct TestSmsWire: Encodable, Sendable { var test: Bool }

public extension APIClient {
    func settingsSms() async throws -> SmsSettingsWire {
        try await get("/api/v1/settings/sms", as: SmsSettingsWire.self)
    }

    func settingsSaveSms(_ body: SmsSettingsWire) async throws -> SmsSettingsWire {
        try await put("/api/v1/settings/sms", body: body, as: SmsSettingsWire.self)
    }

    func settingsSmsTestSend() async throws {
        _ = try await post("/api/v1/settings/sms/test", body: TestSmsWire(test: true), as: EmptyResponse.self)
    }
}

// MARK: - Profile (Settings page variant — canonical is Auth/me)

public struct UserProfileWire: Codable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var email: String?
    public var phone: String?
    public var jobTitle: String?
}

private struct ChangePasswordWire: Encodable, Sendable {
    var currentPassword: String
    var newPassword: String
}

public extension APIClient {
    func settingsMe() async throws -> UserProfileWire {
        try await get("/api/v1/auth/me", as: UserProfileWire.self)
    }

    func settingsSaveMe(_ body: UserProfileWire) async throws -> UserProfileWire {
        try await patch("/api/v1/auth/me", body: body, as: UserProfileWire.self)
    }

    func settingsChangePassword(current: String, new: String) async throws {
        _ = try await put(
            "/api/v1/auth/change-password",
            body: ChangePasswordWire(currentPassword: current, newPassword: new),
            as: EmptyResponse.self
        )
    }

    // §19.1 Avatar upload — POST /api/v1/auth/me/avatar (multipart-form or JSON base64).
    // Uses base64 JSON body to avoid needing multipart implementation here.
    func settingsUploadAvatar(data: Data) async throws -> AvatarUploadResponse {
        let base64 = data.base64EncodedString()
        let body = AvatarUploadWire(imageBase64: base64)
        return try await post("/api/v1/auth/me/avatar", body: body, as: AvatarUploadResponse.self)
    }

    // §19.1 Remove avatar — DELETE /api/v1/auth/me/avatar
    func settingsRemoveAvatar() async throws {
        try await delete("/api/v1/auth/me/avatar")
    }
}

// MARK: - Avatar wire types

private struct AvatarUploadWire: Encodable, Sendable {
    let imageBase64: String
    enum CodingKeys: String, CodingKey { case imageBase64 = "image_base64" }
}

public struct AvatarUploadResponse: Decodable, Sendable {
    public let url: String

    public init(url: String) { self.url = url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = (try? c.decode(String.self, forKey: .url)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case url }
}

// MARK: - Tax Rates

public struct TaxRateWire: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var rate: Double
    public var applyToAll: Bool?
    public var isExempt: Bool?
    public var isArchived: Bool?
}

private struct TaxRateBodyWire: Codable, Sendable {
    var name: String
    var rate: Double
    var applyToAll: Bool
    var isExempt: Bool
}

public extension APIClient {
    func settingsTaxRates() async throws -> [TaxRateWire] {
        try await get("/api/v1/tax-rates", as: [TaxRateWire].self)
    }

    func settingsCreateTaxRate(name: String, rate: Double,
                               applyToAll: Bool, isExempt: Bool) async throws -> TaxRateWire {
        let body = TaxRateBodyWire(name: name, rate: rate, applyToAll: applyToAll, isExempt: isExempt)
        return try await post("/api/v1/tax-rates", body: body, as: TaxRateWire.self)
    }

    func settingsUpdateTaxRate(id: String, name: String, rate: Double,
                               applyToAll: Bool, isExempt: Bool) async throws -> TaxRateWire {
        let body = TaxRateBodyWire(name: name, rate: rate, applyToAll: applyToAll, isExempt: isExempt)
        return try await patch("/api/v1/tax-rates/\(id)", body: body, as: TaxRateWire.self)
    }
}

// MARK: - Danger Zone

private struct RevokeAllWire: Encodable, Sendable { var revokeAll: Bool }
private struct ResetDemoWire: Encodable, Sendable { var confirm: Bool }
private struct DeleteTenantWire: Encodable, Sendable { var pin: String; var confirm: Bool }

public extension APIClient {
    func settingsRevokeAllSessions() async throws {
        _ = try await post("/api/v1/auth/revoke-all", body: RevokeAllWire(revokeAll: true), as: EmptyResponse.self)
    }

    func settingsResetDemo() async throws {
        _ = try await post("/api/v1/tenant/reset-demo", body: ResetDemoWire(confirm: true), as: EmptyResponse.self)
    }

    func settingsDeleteTenant(pin: String) async throws {
        _ = try await post("/api/v1/tenant/delete",
                           body: DeleteTenantWire(pin: pin, confirm: true),
                           as: EmptyResponse.self)
    }
}

// MARK: - Support Contact

public struct SupportContactWire: Decodable, Sendable {
    public var email: String
    public var name: String?
}

public extension APIClient {
    func settingsSupportContact() async throws -> SupportContactWire {
        try await get("/api/v1/tenants/me/support-contact", as: SupportContactWire.self)
    }
}

// MARK: - Changelog / What's New

public struct ChangelogEntryWire: Decodable, Identifiable, Sendable {
    public var id: String
    public var version: String
    public var date: String
    public var title: String
    public var body: String
    public var tag: String?
}

public extension APIClient {
    func settingsChangelog(since: String? = nil) async throws -> [ChangelogEntryWire] {
        var query: [URLQueryItem] = []
        if let since {
            query.append(URLQueryItem(name: "since", value: since))
        }
        return try await get("/api/v1/app/changelog", query: query, as: [ChangelogEntryWire].self)
    }
}
