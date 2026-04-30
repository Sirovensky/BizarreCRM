import Foundation
import Networking

// MARK: - SettingsPagesEndpoints
//
// APIClient extensions for Settings pages that need direct server access.
// ViewModels in this directory call these methods instead of calling
// api.get/post/patch/put directly, satisfying the §20 containment rule.

// MARK: - Language & Region DTOs

public struct LanguageRegionSettings: Codable, Sendable {
    public var locale: String?
    public var timezone: String?
    public var currency: String?
    public var dateFormat: String?
    public var numberFormat: String?

    public init(locale: String?, timezone: String?, currency: String?,
                dateFormat: String?, numberFormat: String?) {
        self.locale = locale
        self.timezone = timezone
        self.currency = currency
        self.dateFormat = dateFormat
        self.numberFormat = numberFormat
    }
}

// MARK: - Company Info DTOs

public struct CompanyInfoDTO: Codable, Sendable {
    public var legalName: String?
    public var dba: String?
    public var address: String?
    public var city: String?
    public var state: String?
    public var zip: String?
    public var phone: String?
    public var website: String?
    public var ein: String?

    public init(legalName: String?, dba: String?, address: String?, city: String?,
                state: String?, zip: String?, phone: String?, website: String?, ein: String?) {
        self.legalName = legalName; self.dba = dba; self.address = address
        self.city = city; self.state = state; self.zip = zip
        self.phone = phone; self.website = website; self.ein = ein
    }
}

// MARK: - Danger Zone DTOs

public struct RevokeAllBody: Encodable, Sendable {
    public let revokeAll: Bool
    public init(revokeAll: Bool) { self.revokeAll = revokeAll }
}

public struct ResetDemoBody: Encodable, Sendable {
    public let confirm: Bool
    public init(confirm: Bool) { self.confirm = confirm }
}

public struct DeleteTenantBody: Encodable, Sendable {
    public let managerPin: String
    public let confirm: Bool
    public init(managerPin: String, confirm: Bool) {
        self.managerPin = managerPin; self.confirm = confirm
    }
}

// MARK: - Payment DTOs

public struct PaymentSettingsDTO: Codable, Sendable {
    public var cashEnabled: Bool?
    public var cardEnabled: Bool?
    public var giftCardEnabled: Bool?
    public var storeCreditEnabled: Bool?
    public var checkEnabled: Bool?
    public var blockChypApiKey: String?
    public var blockChypTerminalName: String?
    // §19.9 — surcharge, tipping, manual-keyed card
    public var cardSurchargeEnabled: Bool?
    public var tippingEnabled: Bool?
    public var tipPresets: [Int]?
    public var manualKeyedCardAllowed: Bool?

    public init(cashEnabled: Bool?, cardEnabled: Bool?, giftCardEnabled: Bool?,
                storeCreditEnabled: Bool?, checkEnabled: Bool?,
                blockChypApiKey: String?, blockChypTerminalName: String?,
                cardSurchargeEnabled: Bool? = nil,
                tippingEnabled: Bool? = nil,
                tipPresets: [Int]? = nil,
                manualKeyedCardAllowed: Bool? = nil) {
        self.cashEnabled = cashEnabled; self.cardEnabled = cardEnabled
        self.giftCardEnabled = giftCardEnabled; self.storeCreditEnabled = storeCreditEnabled
        self.checkEnabled = checkEnabled; self.blockChypApiKey = blockChypApiKey
        self.blockChypTerminalName = blockChypTerminalName
        self.cardSurchargeEnabled = cardSurchargeEnabled
        self.tippingEnabled = tippingEnabled
        self.tipPresets = tipPresets
        self.manualKeyedCardAllowed = manualKeyedCardAllowed
    }
}

// MARK: - SMS DTOs

public struct SmsSettingsDTO: Codable, Sendable {
    public var provider: String?
    public var fromNumber: String?
    public var twilioAccountSid: String?
    public var twilioAuthToken: String?
    public var a2pStatus: String?
    // §19.10 — MMS support toggle
    public var mmsEnabled: Bool?

    public init(provider: String?, fromNumber: String?, twilioAccountSid: String?,
                twilioAuthToken: String?, a2pStatus: String?,
                mmsEnabled: Bool? = nil) {
        self.provider = provider; self.fromNumber = fromNumber
        self.twilioAccountSid = twilioAccountSid; self.twilioAuthToken = twilioAuthToken
        self.a2pStatus = a2pStatus
        self.mmsEnabled = mmsEnabled
    }
}

public struct SmsTestBody: Encodable, Sendable {
    public let test: Bool
    public init(test: Bool) { self.test = test }
}

// MARK: - Profile DTOs

public struct UserProfileDTO: Codable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var email: String?
    public var phone: String?
    public var jobTitle: String?
    public var username: String?
    public var isAdmin: Bool?
    /// §19 — user's assigned role (e.g. "admin", "manager", "technician", "cashier", "viewer").
    public var role: String?
}

public struct UserProfileUpdateDTO: Encodable, Sendable {
    public var firstName: String
    public var lastName: String
    public var displayName: String
    public var email: String
    public var phone: String
    public var jobTitle: String

    public init(firstName: String, lastName: String, displayName: String,
                email: String, phone: String, jobTitle: String) {
        self.firstName = firstName; self.lastName = lastName; self.displayName = displayName
        self.email = email; self.phone = phone; self.jobTitle = jobTitle
    }
}

public struct ChangePasswordDTO: Encodable, Sendable {
    public let currentPassword: String
    public let newPassword: String
    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword; self.newPassword = newPassword
    }
}

// MARK: - Tax DTOs

public struct TaxRateDTO: Codable, Sendable {
    public var id: String
    public var name: String
    public var rate: Double
    public var applyToAll: Bool?
    public var isExempt: Bool?
    public var isArchived: Bool?
}

public struct TaxRateCreateDTO: Encodable, Sendable {
    public var name: String
    public var rate: Double
    public var applyToAll: Bool
    public var isExempt: Bool

    public init(name: String, rate: Double, applyToAll: Bool, isExempt: Bool) {
        self.name = name; self.rate = rate
        self.applyToAll = applyToAll; self.isExempt = isExempt
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Language & Region

    /// `GET /settings/organization` — fetch language & region settings.
    func fetchLanguageRegionSettings() async throws -> LanguageRegionSettings {
        try await get("/settings/organization", as: LanguageRegionSettings.self)
    }

    /// `PUT /settings/organization` — save language & region settings.
    func saveLanguageRegionSettings(_ body: LanguageRegionSettings) async throws -> LanguageRegionSettings {
        try await put("/settings/organization", body: body, as: LanguageRegionSettings.self)
    }

    // MARK: Company Info

    /// `GET /tenant/company` — fetch company information.
    func fetchCompanyInfo() async throws -> CompanyInfoDTO {
        try await get("/tenant/company", as: CompanyInfoDTO.self)
    }

    /// `PATCH /tenant/company` — save company information.
    func saveCompanyInfo(_ body: CompanyInfoDTO) async throws -> CompanyInfoDTO {
        try await patch("/tenant/company", body: body, as: CompanyInfoDTO.self)
    }

    // MARK: Danger Zone

    /// `POST /auth/revoke-all` — revoke all active sessions.
    func revokeAllSessions() async throws {
        _ = try await post("/auth/revoke-all", body: RevokeAllBody(revokeAll: true), as: EmptyResponse.self)
    }

    /// `POST /tenant/reset-demo` — reset demo data to defaults.
    func resetDemoData() async throws {
        _ = try await post("/tenant/reset-demo", body: ResetDemoBody(confirm: true), as: EmptyResponse.self)
    }

    /// `POST /tenant/delete` — permanently delete tenant (requires manager PIN).
    func deleteTenant(managerPin: String) async throws {
        _ = try await post("/tenant/delete", body: DeleteTenantBody(managerPin: managerPin, confirm: true), as: EmptyResponse.self)
    }

    // MARK: Payment Settings

    /// `GET /settings/payment` — fetch payment method settings.
    func fetchPaymentSettings() async throws -> PaymentSettingsDTO {
        try await get("/settings/payment", as: PaymentSettingsDTO.self)
    }

    /// `PUT /settings/payment` — save payment method settings.
    func savePaymentSettings(_ body: PaymentSettingsDTO) async throws -> PaymentSettingsDTO {
        try await put("/settings/payment", body: body, as: PaymentSettingsDTO.self)
    }

    // MARK: SMS Settings

    /// `GET /settings/sms` — fetch SMS provider settings.
    func fetchSmsSettings() async throws -> SmsSettingsDTO {
        try await get("/settings/sms", as: SmsSettingsDTO.self)
    }

    /// `PUT /settings/sms` — save SMS provider settings.
    func saveSmsSettings(_ body: SmsSettingsDTO) async throws -> SmsSettingsDTO {
        try await put("/settings/sms", body: body, as: SmsSettingsDTO.self)
    }

    /// `POST /settings/sms/test` — send a test SMS to the current user's phone.
    func sendTestSms() async throws {
        _ = try await post("/settings/sms/test", body: SmsTestBody(test: true), as: EmptyResponse.self)
    }

    // MARK: Profile

    /// `GET /auth/me` — fetch the current user's profile.
    func fetchUserProfile() async throws -> UserProfileDTO {
        try await get("/auth/me", as: UserProfileDTO.self)
    }

    /// `PATCH /auth/me` — update the current user's profile.
    func updateUserProfile(_ body: UserProfileUpdateDTO) async throws -> UserProfileDTO {
        try await patch("/auth/me", body: body, as: UserProfileDTO.self)
    }

    /// `PUT /auth/change-password` — change the current user's password.
    func changePassword(_ body: ChangePasswordDTO) async throws {
        _ = try await put("/auth/change-password", body: body, as: EmptyResponse.self)
    }

    // MARK: Server health

    /// `GET /health` — ping the server; returns latency in milliseconds.
    func pingHealth() async throws -> Int {
        let start = Date()
        _ = try await get("/health", as: SettingsHealthResponse.self)
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    // MARK: Tax Rates

    /// `GET /tax-rates` — list all tax rates.
    func fetchTaxRates() async throws -> [TaxRateDTO] {
        try await get("/tax-rates", as: [TaxRateDTO].self)
    }

    /// `POST /tax-rates` — create a new tax rate.
    func createTaxRate(_ body: TaxRateCreateDTO) async throws -> TaxRateDTO {
        try await post("/tax-rates", body: body, as: TaxRateDTO.self)
    }

    /// `PATCH /tax-rates/:id` — update an existing tax rate.
    func updateTaxRate(id: String, _ body: TaxRateCreateDTO) async throws -> TaxRateDTO {
        try await patch("/tax-rates/\(id)", body: body, as: TaxRateDTO.self)
    }
}

private struct SettingsHealthResponse: Decodable, Sendable { let status: String? }
