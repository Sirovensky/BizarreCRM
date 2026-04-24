import Foundation

// MARK: - §19.5 OrganizationSettings model

/// All organisation-level settings surfaced by `GET /settings/store`.
/// The server persists these as flat key/value pairs in `store_config`;
/// the iOS layer groups them into one typed model for convenience.
public struct OrganizationSettings: Codable, Sendable, Equatable {

    // MARK: Identity

    /// Public trading name ("Bizarre CRM Repairs").
    public var name: String

    /// Legal / registered entity name (may differ from DBA).
    public var legalName: String

    // MARK: Contact

    /// Street address (single line for simplicity; server key: `address`).
    public var address: String

    /// Main contact phone number.
    public var phone: String

    /// Primary contact / billing e-mail.
    public var email: String

    // MARK: Branding

    /// URL of the uploaded logo (used on receipts, invoices, emails).
    public var logoUrl: String

    // MARK: Legal / financial

    /// Tax ID / EIN / GST number.
    public var taxId: String

    /// ISO 4217 currency code, e.g. "USD", "CAD".
    public var currencyCode: String

    // MARK: Localisation

    /// IANA timezone identifier, e.g. "America/New_York".
    public var timezone: String

    /// BCP-47 locale identifier, e.g. "en_US".
    public var locale: String

    // MARK: - Init

    public init(
        name: String = "",
        legalName: String = "",
        address: String = "",
        phone: String = "",
        email: String = "",
        logoUrl: String = "",
        taxId: String = "",
        currencyCode: String = "USD",
        timezone: String = "America/New_York",
        locale: String = "en_US"
    ) {
        self.name = name
        self.legalName = legalName
        self.address = address
        self.phone = phone
        self.email = email
        self.logoUrl = logoUrl
        self.taxId = taxId
        self.currencyCode = currencyCode
        self.timezone = timezone
        self.locale = locale
    }
}

// MARK: - Wire ↔ domain mapping

extension OrganizationSettings {

    /// Build from the flat `store_config` key/value map returned by
    /// `GET /settings/store` / `GET /settings/config`.
    public init(storeConfig cfg: [String: String]) {
        self.init(
            name:         cfg["store_name"]     ?? "",
            legalName:    cfg["legal_name"]     ?? "",
            address:      cfg["address"]        ?? cfg["store_address"] ?? "",
            phone:        cfg["phone"]          ?? cfg["store_phone"]   ?? "",
            email:        cfg["email"]          ?? cfg["store_email"]   ?? "",
            logoUrl:      cfg["logo_url"]       ?? cfg["store_logo"]    ?? "",
            taxId:        cfg["tax_id"]         ?? cfg["ein"]           ?? "",
            currencyCode: cfg["currency"]       ?? cfg["store_currency"] ?? "USD",
            timezone:     cfg["timezone"]       ?? cfg["store_timezone"] ?? "",
            locale:       cfg["locale"]         ?? ""
        )
    }

    /// Serialise back to the flat key/value pairs expected by
    /// `PUT /settings/store`.
    public func toStoreConfig() -> [String: String] {
        [
            "store_name":     name,
            "legal_name":     legalName,
            "address":        address,
            "phone":          phone,
            "email":          email,
            "logo_url":       logoUrl,
            "tax_id":         taxId,
            "currency":       currencyCode,
            "timezone":       timezone,
            "locale":         locale,
        ]
    }
}
