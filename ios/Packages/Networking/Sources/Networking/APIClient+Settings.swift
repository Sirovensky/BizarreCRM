import Foundation

// MARK: - §19 Settings API endpoints
// Routes grounded from packages/server/src/routes/settings.routes.ts
// Envelope: { success, data, message }

// MARK: - Business profile (store) DTOs

public struct StoreConfigResponse: Decodable, Sendable {
    public var storeName: String?
    public var address: String?
    public var phone: String?
    public var email: String?
    public var timezone: String?
    public var currency: String?
    public var receiptHeader: String?
    public var receiptFooter: String?
    public var logoUrl: String?

    public init(
        storeName: String? = nil,
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        timezone: String? = nil,
        currency: String? = nil,
        receiptHeader: String? = nil,
        receiptFooter: String? = nil,
        logoUrl: String? = nil
    ) {
        self.storeName = storeName
        self.address = address
        self.phone = phone
        self.email = email
        self.timezone = timezone
        self.currency = currency
        self.receiptHeader = receiptHeader
        self.receiptFooter = receiptFooter
        self.logoUrl = logoUrl
    }

    enum CodingKeys: String, CodingKey {
        case storeName = "store_name"
        case address
        case phone
        case email
        case timezone
        case currency
        case receiptHeader = "receipt_header"
        case receiptFooter = "receipt_footer"
        case logoUrl = "logo_url"
    }
}

public struct StoreConfigRequest: Encodable, Sendable {
    public var storeName: String
    public var address: String
    public var phone: String
    public var email: String
    public var timezone: String
    public var currency: String
    public var receiptHeader: String
    public var receiptFooter: String

    public init(
        storeName: String,
        address: String,
        phone: String,
        email: String,
        timezone: String,
        currency: String,
        receiptHeader: String,
        receiptFooter: String
    ) {
        self.storeName = storeName
        self.address = address
        self.phone = phone
        self.email = email
        self.timezone = timezone
        self.currency = currency
        self.receiptHeader = receiptHeader
        self.receiptFooter = receiptFooter
    }

    enum CodingKeys: String, CodingKey {
        case storeName = "store_name"
        case address
        case phone
        case email
        case timezone
        case currency
        case receiptHeader = "receipt_header"
        case receiptFooter = "receipt_footer"
    }
}

// MARK: - Preferences DTOs

/// Keys allowed by PUT /settings/preferences on the server.
public struct UserPreferencesResponse: Codable, Sendable {
    public var theme: String?
    public var defaultView: String?
    public var timezone: String?
    public var language: String?
    public var sidebarCollapsed: Bool?
    public var ticketDefaultSort: String?
    public var ticketDefaultFilter: String?
    public var ticketPageSize: Int?
    public var notificationSound: Bool?
    public var notificationDesktop: Bool?
    public var compactMode: Bool?
    /// Per-user preferred currency code (ISO 4217, e.g. "USD", "EUR").
    /// Overrides the tenant-level currency when set.
    public var preferredCurrency: String?
    /// Per-user date format override (e.g. "MM/dd/yyyy", "dd/MM/yyyy").
    /// Overrides the tenant-level date format when set.
    public var dateFormatOverride: String?
    /// Per-user number format override (e.g. "1,234.56", "1.234,56").
    /// Overrides the tenant-level number format when set.
    public var numberFormatOverride: String?

    public init(
        theme: String? = nil,
        defaultView: String? = nil,
        timezone: String? = nil,
        language: String? = nil,
        sidebarCollapsed: Bool? = nil,
        ticketDefaultSort: String? = nil,
        ticketDefaultFilter: String? = nil,
        ticketPageSize: Int? = nil,
        notificationSound: Bool? = nil,
        notificationDesktop: Bool? = nil,
        compactMode: Bool? = nil,
        preferredCurrency: String? = nil,
        dateFormatOverride: String? = nil,
        numberFormatOverride: String? = nil
    ) {
        self.theme = theme
        self.defaultView = defaultView
        self.timezone = timezone
        self.language = language
        self.sidebarCollapsed = sidebarCollapsed
        self.ticketDefaultSort = ticketDefaultSort
        self.ticketDefaultFilter = ticketDefaultFilter
        self.ticketPageSize = ticketPageSize
        self.notificationSound = notificationSound
        self.notificationDesktop = notificationDesktop
        self.compactMode = compactMode
        self.preferredCurrency = preferredCurrency
        self.dateFormatOverride = dateFormatOverride
        self.numberFormatOverride = numberFormatOverride
    }

    enum CodingKeys: String, CodingKey {
        case theme
        case defaultView = "default_view"
        case timezone
        case language
        case sidebarCollapsed = "sidebar_collapsed"
        case ticketDefaultSort = "ticket_default_sort"
        case ticketDefaultFilter = "ticket_default_filter"
        case ticketPageSize = "ticket_page_size"
        case notificationSound = "notification_sound"
        case notificationDesktop = "notification_desktop"
        case compactMode = "compact_mode"
        case preferredCurrency = "preferred_currency"
        case dateFormatOverride = "date_format_override"
        case numberFormatOverride = "number_format_override"
    }
}

// MARK: - APIClient extension

public extension APIClient {

    // MARK: Business profile (store config)

    /// GET /settings/store — full store config key-value map
    func fetchStoreConfig() async throws -> StoreConfigResponse {
        // Server returns a flat Record<string,string>; decode into typed struct
        try await get("/settings/store", as: StoreConfigResponse.self)
    }

    /// PUT /settings/store — upsert store config fields (admin only)
    @discardableResult
    func updateStoreConfig(_ body: StoreConfigRequest) async throws -> StoreConfigResponse {
        try await put("/settings/store", body: body, as: StoreConfigResponse.self)
    }

    // MARK: User preferences

    /// GET /settings/preferences — all preferences for the current user
    func fetchPreferences() async throws -> UserPreferencesResponse {
        try await get("/settings/preferences", as: UserPreferencesResponse.self)
    }

    /// PUT /settings/preferences — bulk upsert preferences for the current user
    @discardableResult
    func updatePreferences(_ body: UserPreferencesResponse) async throws -> UserPreferencesResponse {
        try await put("/settings/preferences", body: body, as: UserPreferencesResponse.self)
    }
}

